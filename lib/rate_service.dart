import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Indian gold and silver rates fetched from the internet.
class LiveRates {
  /// 24K (999) gold, Rs. per 10 grams.
  final double goldPer10g;

  /// 999 silver, Rs. per gram.
  final double silverPerGram;

  /// Where the rates came from, e.g. "IBJA" or "IBJA + OroPocket".
  final String source;
  final DateTime fetchedAt;

  const LiveRates({
    required this.goldPer10g,
    required this.silverPerGram,
    required this.source,
    required this.fetchedAt,
  });
}

class RateException implements Exception {
  final String message;
  const RateException(this.message);
  @override
  String toString() => message;
}

/// Reads INDIAN gold and silver rates only (never the international price).
///
/// Sources are tried one after another until one works:
///  1. IBJA rates through a public API (ibja-api.vercel.app)
///  2. IBJA rates straight from ibjarates.com
///  3. OroPocket public Indian rate (buy rate, per gram)
/// Gold and silver are looked up separately, so one metal failing does not stop the other.
class RateService {
  static const _ibjaApiGold = 'https://ibja-api.vercel.app/latest';
  static const _ibjaApiSilver = 'https://ibja-api.vercel.app/silver/latest';
  static const _ibjaSite = 'https://www.ibjarates.com/';
  static const _oroUrl = 'https://api.oropocket.com/public/prices';

  static Future<String> _getText(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Android) ShreeJankiApp');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw RateException('The rate server replied with error ${response.statusCode}.');
      }
      return await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    } finally {
      client.close(force: true);
    }
  }

  static Future<dynamic> _getJson(String url) async => jsonDecode(await _getText(url));

  // ---- parsers (separate so they can be tested without internet) ----

  static double? _numOf(dynamic v) {
    if (v is num) return v > 0 ? v.toDouble() : null;
    if (v is String) {
      final d = double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));
      return (d != null && d > 0) ? d : null;
    }
    return null;
  }

  /// IBJA API gold: 999 gold, Rs. per 10 g. Uses the evening (PM) rate when there is one, else the morning one.
  static double? parseIbjaGold(dynamic json) {
    if (json is! Map) return null;
    return _numOf(json['lblGold999_PM']) ?? _numOf(json['lblGold999_AM']);
  }

  /// IBJA API silver: 999 silver, quoted per kg. Returns Rs. per gram.
  static double? parseIbjaSilver(dynamic json) {
    if (json is! Map) return null;
    final perKg = _numOf(json['lblSilver999_PM']) ?? _numOf(json['lblSilver999_AM']);
    return perKg == null ? null : perKg / 1000;
  }

  static double? _htmlValue(String html, String id) {
    final m = RegExp('id="$id"[^>]*>\\s*([0-9][0-9,.]*)\\s*<').firstMatch(html);
    return m == null ? null : _numOf(m.group(1));
  }

  /// ibjarates.com page: gold 999 per 10 g.
  static double? parseIbjaHtmlGold(String html) => _htmlValue(html, 'lblGold999_PM') ?? _htmlValue(html, 'lblGold999_AM');

  /// ibjarates.com page: silver 999 per kg -> Rs. per gram.
  static double? parseIbjaHtmlSilver(String html) {
    final perKg = _htmlValue(html, 'lblSilver999_PM') ?? _htmlValue(html, 'lblSilver999_AM');
    return perKg == null ? null : perKg / 1000;
  }

  /// OroPocket: Rs. per gram buy rate (without GST). [metal] is 'gold' or 'silver'.
  static double? parseOro(dynamic json, String metal) {
    if (json is! Map) return null;
    final data = json['data'];
    if (data is! Map) return null;
    final row = data[metal];
    return row is Map ? _numOf(row['buy']) : null;
  }

  // ---- fetching ----

  /// Tries each source in order and returns the first sensible value with the source's name.
  static Future<(double, String)?> _firstGood(
    List<(String, Future<double?> Function())> attempts,
    double min,
    double max,
    List<Object> errors,
  ) async {
    for (final (name, run) in attempts) {
      try {
        final v = await run();
        if (v != null && v >= min && v <= max) return (v, name);
      } catch (e) {
        errors.add(e);
      }
    }
    return null;
  }

  /// Fetches Indian gold and silver rates. [adjustPercent] is added on top
  /// (e.g. to include GST or your own margin). 0 = the rate as published.
  static Future<LiveRates> fetch({double adjustPercent = 0}) async {
    final memo = <String, Future<dynamic>>{};
    Future<dynamic> json(String url) => memo.putIfAbsent(url, () => _getJson(url));
    Future<String> text(String url) async => (await memo.putIfAbsent(url, () => _getText(url))) as String;

    final errors = <Object>[];
    final gold = await _firstGood([
      ('IBJA', () async => parseIbjaGold(await json(_ibjaApiGold))),
      ('IBJA', () async => parseIbjaHtmlGold(await text(_ibjaSite))),
      ('OroPocket', () async {
        final g = parseOro(await json(_oroUrl), 'gold');
        return g == null ? null : g * 10;
      }),
    ], 20000, 1000000, errors);
    final silver = await _firstGood([
      ('IBJA', () async => parseIbjaSilver(await json(_ibjaApiSilver))),
      ('IBJA', () async => parseIbjaHtmlSilver(await text(_ibjaSite))),
      ('OroPocket', () async => parseOro(await json(_oroUrl), 'silver')),
    ], 10, 5000, errors);

    if (gold == null && silver == null) {
      if (errors.any((e) => e is SocketException)) {
        throw const RateException('No internet connection. Check your data / Wi-Fi and try again.');
      }
      if (errors.any((e) => e is TimeoutException)) {
        throw const RateException('The rate servers took too long. Try again in a moment.');
      }
      throw const RateException('Could not get Indian rates right now. You can set them yourself instead.');
    }
    if (gold == null) {
      throw const RateException('Could not get the gold rate right now. You can set it yourself instead.');
    }
    if (silver == null) {
      throw const RateException('Could not get the silver rate right now. You can set it yourself instead.');
    }

    final factor = 1 + adjustPercent / 100;
    final names = {gold.$2, silver.$2}.join(' + ');
    return LiveRates(
      goldPer10g: (gold.$1 * factor).roundToDouble(),
      silverPerGram: double.parse((silver.$1 * factor).toStringAsFixed(2)),
      source: names,
      fetchedAt: DateTime.now(),
    );
  }
}
