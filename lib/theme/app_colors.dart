import 'package:flutter/material.dart';

/// ألوان هوية تعاونوا.
abstract final class AppColors {
  static const navy = Color(0xFF1E3A8A); // الأساسي: الأزرار والعناوين
  static const blue = Color(0xFF2563EB); // الثانوي: الروابط والتفاعل
  static const sky = Color(0xFFEFF6FF); // خلفيات فاتحة وكروت
  static const gold = Color(0xFFD4A537); // الأوسمة والاحتفال (تعبئة فقط، مش نص)

  static const background = Color(0xFFF5F8FD);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFDBE3F0);
  static const text = Color(0xFF0F172A);
  static const textMuted = Color(0xFF475569);

  // حالات الأجزاء في لوحة المجموعة
  static const statusDone = Color(0xFF15803D);
  static const statusInProgress = Color(0xFFFBBF24);
  static const statusLate = Color(0xFFB91C1C);
  static const statusEmpty = Color(0xFFE2E8F0);
}
