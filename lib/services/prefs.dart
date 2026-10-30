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
  Future<void> setLocale(Locale l) => _p.setString('locale', l.languageCode);

  double get readerFontSize => _p.getDouble('readerFontSize') ?? 26;
  Future<void> setReaderFontSize(double v) => _p.setDouble('readerFontSize', v);

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
}
