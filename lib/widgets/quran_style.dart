import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/quran_repository.dart';

/// ستايل نص المصحف حسب الخط المختار (مصحف المدينة ملف جوه التطبيق، والباقي من Google Fonts).
TextStyle quranTextStyle(String font, {required double fontSize, required Color color}) {
  if (font == madinahFont) {
    return TextStyle(fontFamily: madinahFont, fontSize: fontSize, height: 2.0, color: color);
  }
  return GoogleFonts.getFont(font, fontSize: fontSize, height: 2.1, color: color);
}
