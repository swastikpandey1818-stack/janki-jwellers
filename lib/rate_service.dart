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

/// Reads the international gold and silver price (US dollars per troy ounce) and the
/// dollar-to-rupee rate from free public services, and converts them to Rs. per 10 g / per gram.
///
/// The result is the INTERNATIONAL price in rupees. Indian shop rates usually run higher
/// (import duty, GST, local premium), so the app lets the seller add an adjustment %.
class RateService {
  static const double _gramsPerTroyOunce = 31.1034768;

  static const _goldUrl = 'https://api.gold-api.com/price/XAU';
  static const _silverUrl = 'https://api.gold-api.com/price/XAG';
  static const _fxUrls = [
    'https://open.er-api.com/v6/latest/USD',
    'https://api.frankfurter.dev/v1/latest?base=USD&symbols=INR',
  ];

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw RateException('The rate server replied with error ${response.statusCode}.');
      }
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const RateException('The rate server sent an unexpected reply.');
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  static Future<double> _usdPerOunce(String url, {required double min, required double max}) async {
    final json = await _getJson(url);
    final price = json['price'];
    if (price is num && price >= min && price <= max) return price.toDouble();
    throw const RateException('The rate server sent a price that looks wrong.');
  }

  static Future<double> _usdInr() async {
    Object? lastError;
    for (final url in _fxUrls) {
      try {
        final json = await _getJson(url);
        final rates = json['rates'];
        if (rates is Map) {
          final inr = rates['INR'];
          if (inr is num && inr > 30 && inr < 300) return inr.toDouble();
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    throw const RateException('Could not read the dollar-to-rupee rate.');
  }

  /// Fetches gold, silver and the dollar rate, and converts. [adjustPercent] is added on top
  /// (use it to match your local market, e.g. 6 for import duty).
  static Future<LiveRates> fetch({double adjustPercent = 0}) async {
    try {
      final results = await Future.wait<double>([
        _usdPerOunce(_goldUrl, min: 100, max: 100000),
        _usdPerOunce(_silverUrl, min: 1, max: 5000),
        _usdInr(),
      ]);
      final goldUsd = results[0];
      final silverUsd = results[1];
      final fx = results[2];
      final factor = 1 + adjustPercent / 100;
      final goldPerGram = goldUsd * fx / _gramsPerTroyOunce;
      final silverPerGram = silverUsd * fx / _gramsPerTroyOunce;
      return LiveRates(
        goldPer10g: (goldPerGram * 10 * factor).roundToDouble(),
        silverPerGram: double.parse((silverPerGram * factor).toStringAsFixed(2)),
        usdInr: fx,
        fetchedAt: DateTime.now(),
      );
    } on RateException {
      rethrow;
    } on SocketException {
      throw const RateException('No internet connection. Check your data / Wi-Fi and try again.');
    } on TimeoutException {
      throw const RateException('The rate server took too long. Try again in a moment.');
    } on HandshakeException {
      throw const RateException('Could not make a secure connection. Check the phone date and time.');
    } catch (_) {
      throw const RateException('Could not fetch the rates right now. You can set them yourself instead.');
    }
  }
}
