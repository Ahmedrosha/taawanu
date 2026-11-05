import 'package:flutter/material.dart';

import '../services/prefs.dart';
import 'app_colors.dart';

/// ألوان تظليل الآية/الكلمة في القراءة: (فاتح، غامق) لكل لون. الغامق أقوى عشان يبان على الخلفية الغامقة.
const highlightPalette = <String, (Color, Color)>{
  'gold': (Color(0xFFF6E3A8), Color(0xFF6E5716)),
  'yellow': (Color(0xFFFFF176), Color(0xFF857A10)),
  'green': (Color(0xFFC6EFCF), Color(0xFF22643A)),
  'blue': (Color(0xFFCFE2FF), Color(0xFF214E86)),
  'pink': (Color(0xFFF9D0E4), Color(0xFF7E3159)),
};

Color highlightColorFor(String id, {bool? dark}) {
  final c = highlightPalette[id] ?? highlightPalette['gold']!;
  return (dark ?? AppColors.isDark) ? c.$2 : c.$1;
}

/// لون التظليل المختار في الإعدادات.
Color get readHighlightColor => highlightColorFor(Prefs.instance.highlightColor);
