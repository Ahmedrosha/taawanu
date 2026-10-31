import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات محفوظة على الجهاز: اللغة، وحجم خط المصحف، وعدادات الأذكار.
class Prefs {
  Prefs._(this._p);

  static late Prefs instance;

  final SharedPreferences _p;

  static Future<void> init() async {
    instance = Prefs._(await SharedPreferences.getInstance());
  }

  Locale get locale => Locale(_p.getString('locale') ?? 'ar');

  /// system | light | dark
  ThemeMode get themeMode => ThemeMode.values.firstWhere((m) => m.name == _p.getString('themeMode'), orElse: () => ThemeMode.system);
  Future<void> setThemeMode(String v) => _p.setString('themeMode', v);
  Future<void> setLocale(Locale l) => _p.setString('locale', l.languageCode);

  double get readerFontSize => _p.getDouble('readerFontSize') ?? 26;
  Future<void> setReaderFontSize(double v) => _p.setDouble('readerFontSize', v);

  /// خط المصحف (اسم الخط في Google Fonts).
  /// 'KFGQPC Hafs' = خط مصحف المدينة (ملف جوه التطبيق)، والباقي من Google Fonts.
  static const readerFonts = ['KFGQPC Hafs', 'Amiri Quran', 'Scheherazade New', 'Amiri', 'Noto Naskh Arabic'];
  String get readerFont {
    final v = _p.getString('readerFont');
    return readerFonts.contains(v) ? v! : 'Amiri Quran';
  }

  Future<void> setReaderFont(String v) => _p.setString('readerFont', v);

  /// عدادات الأذكار بتتصفر كل يوم.
  Map<String, int> adhkarCounts(String day) {
    if (_p.getString('adhkarDay') != day) return {};
    final raw = _p.getStringList('adhkarCounts') ?? const [];
    return {
      for (final e in raw)
        if (e.contains('=')) e.split('=').first: int.tryParse(e.split('=').last) ?? 0,
    };
  }

  Future<void> setAdhkarCounts(String day, Map<String, int> counts) async {
    await _p.setString('adhkarDay', day);
    await _p.setStringList('adhkarCounts', [for (final e in counts.entries) '${e.key}=${e.value}']);
  }

  // ---------- الصلاة ----------
  // الموقع بيتحفظ على الجهاز بس، ومبيتبعتش للسيرفر.

  double? get prayerLat => _p.getDouble('prayerLat');
  double? get prayerLng => _p.getDouble('prayerLng');

  /// اسم المكان (بالعربي والإنجليزي) لو اتحدد من القائمة أو لقينا مدينة قريبة.
  String? get prayerPlaceAr => _p.getString('prayerPlaceAr');
  String? get prayerPlaceEn => _p.getString('prayerPlaceEn');

  Future<void> setPrayerLocation(double lat, double lng, {String? placeAr, String? placeEn}) async {
    await _p.setDouble('prayerLat', lat);
    await _p.setDouble('prayerLng', lng);
    if (placeAr != null) {
      await _p.setString('prayerPlaceAr', placeAr);
    } else {
      await _p.remove('prayerPlaceAr');
    }
    if (placeEn != null) {
      await _p.setString('prayerPlaceEn', placeEn);
    } else {
      await _p.remove('prayerPlaceEn');
    }
  }

  /// طريقة الحساب (null = تلقائي حسب المكان).
  String? get prayerMethod => _p.getString('prayerMethod');
  Future<void> setPrayerMethod(String? v) => v == null ? _p.remove('prayerMethod') : _p.setString('prayerMethod', v);

  bool get asrHanafi => _p.getBool('asrHanafi') ?? false;
  Future<void> setAsrHanafi(bool v) => _p.setBool('asrHanafi', v);

  // ---------- تنبيهات الصلاة ----------

  bool get prayerAlerts => _p.getBool('prayerAlerts') ?? false;
  Future<void> setPrayerAlerts(bool v) => _p.setBool('prayerAlerts', v);

  /// الصلوات اللي عليها تنبيه (أسماء الـenum). الافتراضي: الخمسة.
  Set<String> get prayerAlertsFor =>
      (_p.getStringList('prayerAlertsFor') ?? const ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']).toSet();
  Future<void> setPrayerAlertsFor(Set<String> v) => _p.setStringList('prayerAlertsFor', v.toList());

  /// تذكير قبل الصلاة بالدقايق (٠ = من غير).
  int get prayerReminderMinutes => _p.getInt('prayerReminderMinutes') ?? 0;
  Future<void> setPrayerReminderMinutes(int v) => _p.setInt('prayerReminderMinutes', v);

  // ---------- مكان القراءة ----------
  // آخر آية كانت أول الشاشة في كل ورد: "ربع:سورة:آية".

  String? readPosition(String key) => _p.getString('readPos:$key');
  Future<void> setReadPosition(String key, String v) => _p.setString('readPos:$key', v);
  Future<void> clearReadPosition(String key) => _p.remove('readPos:$key');
}
