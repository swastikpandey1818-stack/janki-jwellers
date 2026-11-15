import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Rates fetched from the internet, already converted to rupees.
class LiveRates {
  /// 24K gold, Rs. per 10 grams.
  final double goldPer10g;

  /// Silver, Rs. per gram.
  final double silverPerGram;

  /// Rupees per US dollar used for the conversion.
  final double usdInr;
  final DateTime fetchedAt;

  const LiveRates({
    required this.goldPer10g,
    required this.silverPerGram,
    required this.usdInr,
    required this.fetchedAt,
  });
}

class RateException implements Exception {
  final String message;
  const RateException(this.message);
  @override
  String toString() => message;
}

/// Reads the international gold and silver price from several free public services (it tries
/// them one by one until one works) and converts it to Rs. per 10 g / per gram.
///
/// The result is the INTERNATIONAL price in rupees. Indian shop rates usually run higher
/// (import duty, GST, local premium), so the app lets the seller add an adjustment %.
class RateService {
  static const double _gramsPerTroyOunce = 31.1034768;

  // Dollar -> rupee, tried in this order.
  static const _fxUrls = [
    'https://open.er-api.com/v6/latest/USD',
    'https://api.frankfurter.dev/v1/latest?base=USD&symbols=INR',
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
    'https://latest.currency-api.pages.dev/v1/currencies/usd.json',
  ];

  static Future<dynamic> _getAny(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Android) ShreeJankiApp');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw RateException('The rate server replied with error ${response.statusCode}.');
      }
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  // ---- parsers (kept separate so they can be tested without internet) ----

  static double? _positive(dynamic v) => (v is num && v > 0) ? v.toDouble() : null;

  /// gold-api.com: {"price": 4000.5, ...} in US dollars per troy ounce.
  static double? parseGoldApi(dynamic json) => json is Map ? _positive(json['price']) : null;

  /// Swissquote public feed: a list whose first item holds bid / ask prices in US dollars per ounce.
  static double? parseSwissquote(dynamic json) {
    if (json is! List || json.isEmpty || json.first is! Map) return null;
    final profiles = (json.first as Map)['spreadProfilePrices'];
    if (profiles is! List || profiles.isEmpty || profiles.first is! Map) return null;
    final p = profiles.first as Map;
    final bid = _positive(p['bid']);
    final ask = _positive(p['ask']);
    if (bid != null && ask != null) return (bid + ask) / 2;
    return bid ?? ask;
  }

  /// Yahoo Finance chart (futures): US dollars per ounce.
  static double? parseYahoo(dynamic json) {
    if (json is! Map) return null;
    final chart = json['chart'];
    if (chart is! Map) return null;
    final result = chart['result'];
    if (result is! List || result.isEmpty || result.first is! Map) return null;
    final meta = (result.first as Map)['meta'];
    return meta is Map ? _positive(meta['regularMarketPrice']) : null;
  }

  /// fawazahmed0 currency API for "xau" / "xag": 1 ounce in rupees.
  static double? parseCurrencyApi(dynamic json, String code) {
    if (json is! Map) return null;
    final row = json[code];
    return row is Map ? _positive(row['inr']) : null;
  }

  /// Rupees per dollar from either the exchange-rate services or the currency API.
  static double? parseFx(dynamic json) {
    if (json is! Map) return null;
    dynamic inr;
    final rates = json['rates'];
    if (rates is Map) inr = rates['INR'];
    final usd = json['usd'];
    if (inr == null && usd is Map) inr = usd['inr'];
    return (inr is num && inr > 30 && inr < 300) ? inr.toDouble() : null;
  }

  // ---- fetching with fallbacks ----

  static double? _usdInrCache;

  static Future<double> _usdInr() async {
    final cached = _usdInrCache;
    if (cached != null) return cached;
    for (final url in _fxUrls) {
      try {
        final v = parseFx(await _getAny(url));
        if (v != null) return _usdInrCache = v;
      } catch (_) {
        // Try the next service.
      }
    }
    throw const RateException('Could not read the dollar-to-rupee rate.');
  }

  /// Rupees for one troy ounce of [metal] ('XAU' gold, 'XAG' silver). Tries every source in turn.
  static Future<double> _inrPerOunce(String metal) async {
    final isGold = metal == 'XAU';
    final minUsd = isGold ? 100.0 : 1.0;
    final maxUsd = isGold ? 100000.0 : 5000.0;
    final code = metal.toLowerCase();

    // Each source gives US dollars per ounce, unless it is the currency API (rupees directly).
    final usdSources = <(String, double? Function(dynamic))>[
      ('https://api.gold-api.com/price/$metal', parseGoldApi),
      ('https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/$metal/USD', parseSwissquote),
      ('https://query1.finance.yahoo.com/v8/finance/chart/${isGold ? 'GC=F' : 'SI=F'}', parseYahoo),
    ];
    final inrUrls = [
      'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/$code.json',
      'https://latest.currency-api.pages.dev/v1/currencies/$code.json',
    ];

    Object? lastError;
    for (final (url, parse) in usdSources) {
      try {
        final usd = parse(await _getAny(url));
        if (usd != null && usd >= minUsd && usd <= maxUsd) return usd * await _usdInr();
      } catch (e) {
        lastError = e;
      }
    }
    for (final url in inrUrls) {
      try {
        final inr = parseCurrencyApi(await _getAny(url), code);
        if (inr != null && inr >= minUsd * 30 && inr <= maxUsd * 300) return inr;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    throw const RateException('None of the rate servers sent a usable price.');
  }

  /// Fetches gold and silver and converts. [adjustPercent] is added on top
  /// (use it to match your local market, e.g. 6 for import duty).
  static Future<LiveRates> fetch({double adjustPercent = 0}) async {
    try {
      _usdInrCache = null;
      final goldInr = await _inrPerOunce('XAU');
      final silverInr = await _inrPerOunce('XAG');
      final factor = 1 + adjustPercent / 100;
      return LiveRates(
        goldPer10g: (goldInr / _gramsPerTroyOunce * 10 * factor).roundToDouble(),
        silverPerGram: double.parse((silverInr / _gramsPerTroyOunce * factor).toStringAsFixed(2)),
        usdInr: _usdInrCache ?? 0,
        fetchedAt: DateTime.now(),
      );
    } on RateException {
      rethrow;
    } on SocketException {
      throw const RateException('No internet connection. Check your data / Wi-Fi and try again.');
    } on TimeoutException {
      throw const RateException('The rate servers took too long. Try again in a moment.');
    } on HandshakeException {
      throw const RateException('Could not make a secure connection. Check the phone date and time.');
    } catch (_) {
      throw const RateException('Could not fetch the rates right now. You can set them yourself instead.');
    }
  }
}
