import 'package:flutter/material.dart';

import 'app_colors.dart';

/// ألوان أحكام التجويد في النص المتصل (فاتحة وغامقة)، بنفس ترتيب الأنواع في tajweed.json.
const _light = [
  Color(0xFFA0161B), // مد لازم ٦
  Color(0xFFE0262B), // مد واجب/منفصل ٤-٥
  Color(0xFFE8791A), // مد جائز ٢/٤/٦
  Color(0xFFB8860B), // مد طبيعي ٢
  Color(0xFF169C3B), // غنة وإخفاء وإقلاب وإدغام بغنة
  Color(0xFF1E88E5), // قلقلة
  Color(0xFF9AA0A6), // لا يُنطق
];
const _dark = [
  Color(0xFFFF6B6B),
  Color(0xFFFF8A80),
  Color(0xFFFFB74D),
  Color(0xFFE6C35C),
  Color(0xFF5ED68A),
  Color(0xFF64B5F6),
  Color(0xFF7D8590),
];

/// ألوان الأحكام الأساسية (قبل ضبط التباين).
List<Color> tajweedPalette({required bool dark}) => dark ? _dark : _light;

/// أقل تباين مقبول بين الحرف والخلفية (WCAG للخط الكبير: ٣).
const _minContrast = 3.0;

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

final _cache = <(int, int, double), Color>{};

/// نفس اللون، بس لو مش باين كفاية على الخلفية بنفتّحه (خلفية غامقة) أو نغمّقه (فاتحة) لحد ما يبان.
/// كده أي لون تجويد فوق أي تظليل أو صفحة، في الوضع الفاتح والغامق، بيفضل مقروء ومحافظ على لونه.
Color readableOn(Color c, Color bg, {double min = _minContrast}) {
  final key = (c.toARGB32(), bg.toARGB32(), min);
  final hit = _cache[key];
  if (hit != null) return hit;
  var out = c;
  if (contrastRatio(c, bg) < min) {
    final lighten = bg.computeLuminance() < 0.35;
    var h = HSLColor.fromColor(c);
    out = lighten ? Colors.white : Colors.black;
    for (var i = 0; i < 25; i++) {
      h = h.withLightness((h.lightness + (lighten ? 0.03 : -0.03)).clamp(0.0, 1.0));
      final cc = h.toColor();
      if (contrastRatio(cc, bg) >= min) {
        out = cc;
        break;
      }
    }
  }
  if (_cache.length > 200) _cache.clear();
  return _cache[key] = out;
}

/// لون الحكم على خلفية معيّنة ([on]: التظليل، وإلا لون الصفحة).
Color tajweedColor(int kind, {Color? on}) {
  final p = AppColors.isDark ? _dark : _light;
  return readableOn(p[kind.clamp(0, p.length - 1)], on ?? AppColors.paper);
}
