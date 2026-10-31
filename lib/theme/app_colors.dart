import 'package:flutter/material.dart';

/// لوحة ألوان واحدة (فاتح أو غامق).
class AppPalette {
  const AppPalette({
    required this.navy,
    required this.accent,
    required this.blue,
    required this.sky,
    required this.gold,
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.statusDone,
    required this.statusInProgress,
    required this.statusLate,
    required this.statusEmpty,
    required this.statusPending,
    required this.mutedLine,
    required this.track,
    required this.neutralTint,
    required this.doneTint,
    required this.doneBorder,
    required this.goldTint,
    required this.goldInk,
    required this.goldText,
    required this.paper,
    required this.paperLine,
    required this.paperLabel,
    required this.whatsappBubble,
  });

  final Color navy, accent, blue, sky, gold;
  final Color background, surface, border, text, textMuted;
  final Color statusDone, statusInProgress, statusLate, statusEmpty, statusPending, mutedLine;
  final Color track, neutralTint, doneTint, doneBorder, goldTint, goldInk, goldText;
  final Color paper, paperLine, paperLabel, whatsappBubble;

  static const light = AppPalette(
    navy: Color(0xFF1E3A8A),
    accent: Color(0xFF1E3A8A),
    blue: Color(0xFF2563EB),
    sky: Color(0xFFEFF6FF),
    gold: Color(0xFFD4A537),
    background: Color(0xFFF5F8FD),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFDBE3F0),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
    statusDone: Color(0xFF15803D),
    statusInProgress: Color(0xFFFBBF24),
    statusLate: Color(0xFFB91C1C),
    statusEmpty: Color(0xFFE2E8F0),
    statusPending: Color(0xFFCBD5E1),
    mutedLine: Color(0xFF94A3B8),
    track: Color(0xFFE2E8F0),
    neutralTint: Color(0xFFF1F5F9),
    doneTint: Color(0xFFE8F5EC),
    doneBorder: Color(0xFFA7D7B5),
    goldTint: Color(0xFFFDF6E3),
    goldInk: Color(0xFF8A6A14),
    goldText: Color(0xFF5C4708),
    paper: Color(0xFFFFFDF7),
    paperLine: Color(0xFFECE6D6),
    paperLabel: Color(0xFF8A7A4E),
    whatsappBubble: Color(0xFFDCF8C6),
  );

  static const dark = AppPalette(
    navy: Color(0xFF2544A3),
    accent: Color(0xFF8FB3FF),
    blue: Color(0xFF60A5FA),
    sky: Color(0xFF1A2744),
    gold: Color(0xFFD4A537),
    background: Color(0xFF0B1220),
    surface: Color(0xFF141D2F),
    border: Color(0xFF263350),
    text: Color(0xFFE6EDF7),
    textMuted: Color(0xFF9AA8BD),
    statusDone: Color(0xFF22A35A),
    statusInProgress: Color(0xFFFBBF24),
    statusLate: Color(0xFFE5484D),
    statusEmpty: Color(0xFF2A3550),
    statusPending: Color(0xFF4A5875),
    mutedLine: Color(0xFF5B6B86),
    track: Color(0xFF26324A),
    neutralTint: Color(0xFF1C2638),
    doneTint: Color(0xFF12301F),
    doneBorder: Color(0xFF2F6B45),
    goldTint: Color(0xFF2E2614),
    goldInk: Color(0xFFD9B65A),
    goldText: Color(0xFFE8CF8A),
    paper: Color(0xFF16140F),
    paperLine: Color(0xFF3A352A),
    paperLabel: Color(0xFFB8A877),
    whatsappBubble: Color(0xFF005C4B),
  );
}

/// ألوان هوية تعاونوا. بتتبع الوضع الحالي (فاتح/غامق)؛ التطبيق بيبني الشاشات من جديد لما الوضع يتغير.
abstract final class AppColors {
  static AppPalette _p = AppPalette.light;

  static bool get isDark => identical(_p, AppPalette.dark);

  static void use(Brightness b) => _p = b == Brightness.dark ? AppPalette.dark : AppPalette.light;

  /// تعبئة الأزرار والكروت الأساسية (أزرق كحلي في الوضعين).
  static Color get navy => _p.navy;

  /// النصوص والأيقونات المميزة فوق الخلفيات العادية.
  static Color get accent => _p.accent;
  static Color get blue => _p.blue;
  static Color get sky => _p.sky;
  static Color get gold => _p.gold;

  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get border => _p.border;
  static Color get text => _p.text;
  static Color get textMuted => _p.textMuted;

  // حالات الأجزاء في لوحة المجموعة
  static Color get statusDone => _p.statusDone;
  static Color get statusInProgress => _p.statusInProgress;
  static Color get statusLate => _p.statusLate;
  static Color get statusEmpty => _p.statusEmpty;
  static Color get statusPending => _p.statusPending;
  static Color get mutedLine => _p.mutedLine;

  static Color get track => _p.track;
  static Color get neutralTint => _p.neutralTint;
  static Color get doneTint => _p.doneTint;
  static Color get doneBorder => _p.doneBorder;
  static Color get goldTint => _p.goldTint;
  static Color get goldInk => _p.goldInk;
  static Color get goldText => _p.goldText;

  // شاشة القراءة
  static Color get paper => _p.paper;
  static Color get paperLine => _p.paperLine;
  static Color get paperLabel => _p.paperLabel;

  static Color get whatsappBubble => _p.whatsappBubble;
}
