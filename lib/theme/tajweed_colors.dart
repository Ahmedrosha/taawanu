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

Color tajweedColor(int kind) {
  final p = AppColors.isDark ? _dark : _light;
  return p[kind.clamp(0, p.length - 1)];
}
