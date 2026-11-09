import 'dart:convert';
import 'dart:io';

import 'package:hijri/hijri_calendar.dart';

/// بيانات حاسبة الزكاة: بتتحفظ على الموبايل بس (مبتتبعتش للسيرفر).
class ZakatData {
  ZakatData({
    Map<String, double>? values,
    this.currency = 'EGP',
    this.nisab = 'gold',
    this.includeJewelry = false,
    this.hawlStart,
    this.goldOverride,
    this.silverOverride,
  }) : values = values ?? {};

  /// الخانات بالعملة المختارة (والدهب والفضة بالجرام).
  final Map<String, double> values;
  String currency;
  String nisab;
  bool includeJewelry;
  DateTime? hawlStart;

  /// سعر جرام الدهب عيار ٢٤ / الفضة لو كتبه بإيده (بالعملة المختارة).
  double? goldOverride;
  double? silverOverride;

  double v(String k) => values[k] ?? 0;

  Map<String, dynamic> toJson() => {
        'values': values,
        'currency': currency,
        'nisab': nisab,
        'includeJewelry': includeJewelry,
        'hawlStart': hawlStart?.toIso8601String(),
        'goldOverride': goldOverride,
        'silverOverride': silverOverride,
      };

  static ZakatData fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return ZakatData();
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      return ZakatData(
        values: {for (final e in ((d['values'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toDouble()},
        currency: d['currency'] as String? ?? 'EGP',
        nisab: d['nisab'] as String? ?? 'gold',
        includeJewelry: d['includeJewelry'] as bool? ?? false,
        hawlStart: DateTime.tryParse(d['hawlStart'] as String? ?? ''),
        goldOverride: (d['goldOverride'] as num?)?.toDouble(),
        silverOverride: (d['silverOverride'] as num?)?.toDouble(),
      );
    } catch (_) {
      return ZakatData();
    }
  }
}

/// أسعار جرام الدهب عيار ٢٤ والفضة بالجنيه والدولار.
class MetalPrices {
  const MetalPrices({required this.gold, required this.silver, required this.date});

  /// العملة → سعر الجرام.
  final Map<String, double> gold;
  final Map<String, double> silver;
  final String date;

  static const _ounce = 31.1034768;
  static const _sources = [
    'https://latest.currency-api.pages.dev/v1',
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1',
  ];

  String toJson() => jsonEncode({'gold': gold, 'silver': silver, 'date': date});

  static MetalPrices? fromJson(String? raw) {
    if (raw == null) return null;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      Map<String, double> m(Object? x) => {for (final e in (x as Map).entries) e.key as String: (e.value as num).toDouble()};
      return MetalPrices(gold: m(d['gold']), silver: m(d['silver']), date: d['date'] as String);
    } catch (_) {
      return null;
    }
  }

  /// السعر العالمي (من غير مصنعية) محوّل بسعر الصرف.
  static Future<MetalPrices?> fetch() async {
    for (final base in _sources) {
      try {
        final xau = await _get('$base/currencies/xau.json');
        final xag = await _get('$base/currencies/xag.json');
        final g = xau['xau'] as Map<String, dynamic>;
        final s = xag['xag'] as Map<String, dynamic>;
        return MetalPrices(
          gold: {for (final c in ['egp', 'usd']) c.toUpperCase(): (g[c] as num).toDouble() / _ounce},
          silver: {for (final c in ['egp', 'usd']) c.toUpperCase(): (s[c] as num).toDouble() / _ounce},
          date: xau['date'] as String? ?? '',
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}

/// نتيجة الحساب.
class ZakatResult {
  const ZakatResult({required this.goldValue, required this.silverValue, required this.total, required this.nisab, required this.due});
  final double goldValue;
  final double silverValue;
  final double total;
  final double nisab;
  final double due;
  bool get reached => total >= nisab && nisab > 0;
}

ZakatResult computeZakat(ZakatData d, double gold24, double silverGram) {
  final grams = d.v('gold24') + d.v('gold21') * 21 / 24 + d.v('gold18') * 18 / 24 + (d.includeJewelry ? d.v('jewelry21') * 21 / 24 : 0);
  final goldValue = grams * gold24;
  final silverValue = d.v('silver') * silverGram;
  const money = ['cash', 'bank', 'deposits', 'stocks', 'inventory', 'businessCash', 'receivables'];
  final total = money.fold<double>(0, (a, k) => a + d.v(k)) + goldValue + silverValue - d.v('debts');
  final nisab = d.nisab == 'silver' ? 595 * silverGram : 85 * gold24;
  final due = total >= nisab && nisab > 0 ? total * 0.025 : 0.0;
  return ZakatResult(goldValue: goldValue, silverValue: silverValue, total: total, nisab: nisab, due: due);
}

/// الحول الجاي: سنة هجرية من تاريخ بلوغ النصاب (ولو عدّى، اللي بعده).
DateTime nextHawl(DateTime start, DateTime now) {
  final h = HijriCalendar.fromDate(start);
  var year = h.hYear + 1;
  while (true) {
    final probe = HijriCalendar()
      ..hYear = year
      ..hMonth = h.hMonth
      ..hDay = 1;
    final len = probe.getDaysInMonth(year, h.hMonth);
    final g = HijriCalendar().hijriToGregorian(year, h.hMonth, h.hDay.clamp(1, len));
    if (!g.isBefore(DateTime(now.year, now.month, now.day))) return g;
    year++;
  }
}

String hijriLabel(DateTime d, String lang) {
  HijriCalendar.setLocal(lang == 'ar' ? 'ar' : 'en');
  final h = HijriCalendar.fromDate(d);
  return '${h.hDay} ${h.longMonthName} ${h.hYear}';
}
