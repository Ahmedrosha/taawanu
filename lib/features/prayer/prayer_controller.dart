import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hijri/hijri_calendar.dart';

import '../../services/prefs.dart';
import 'prayer_times.dart';

enum LocateResult { ok, serviceOff, denied, deniedForever, failed }

/// إعدادات الصلاة والموقع (محفوظة على الجهاز)، مشتركة بين تبويب الصلاة وكارت الرئيسية.
class PrayerController extends ChangeNotifier {
  PrayerController._();

  static final PrayerController instance = PrayerController._();

  Prefs get _prefs => Prefs.instance;

  bool get hasLocation => _prefs.prayerLat != null && _prefs.prayerLng != null;
  double get lat => _prefs.prayerLat ?? 0;
  double get lng => _prefs.prayerLng ?? 0;

  String? placeName(String locale) => locale == 'en' ? _prefs.prayerPlaceEn : _prefs.prayerPlaceAr;

  bool get methodIsAuto => _prefs.prayerMethod == null;

  PrayerMethodId get method {
    final saved = _prefs.prayerMethod;
    if (saved != null) {
      for (final m in PrayerMethodId.values) {
        if (m.name == saved) return m;
      }
    }
    return defaultMethodFor(lat, lng);
  }

  bool get asrHanafi => _prefs.asrHanafi;

  PrayerDay timesFor(DateTime day) => computePrayerTimes(
        date: day,
        lat: lat,
        lng: lng,
        method: method,
        asrHanafi: asrHanafi,
        ramadan: isRamadan(day),
      );

  /// رمضان حسب تقويم أم القرى.
  static bool isRamadan(DateTime day) {
    try {
      return HijriCalendar.fromDate(DateTime(day.year, day.month, day.day)).hMonth == 9;
    } catch (_) {
      return false;
    }
  }

  /// الصلاة الجاية (من غير الشروق) ووقتها.
  (Prayer, DateTime) next(DateTime now) {
    final today = timesFor(now);
    for (final p in [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha]) {
      if (today[p].isAfter(now.toUtc())) return (p, today[p]);
    }
    final tomorrow = timesFor(now.add(const Duration(days: 1)));
    return (Prayer.fajr, tomorrow[Prayer.fajr]);
  }

  /// موقع تقريبي من الجهاز (دقة منخفضة تكفي للمواقيت والقبلة).
  Future<LocateResult> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocateResult.serviceOff;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return LocateResult.denied;
      if (perm == LocationPermission.deniedForever) return LocateResult.deniedForever;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
      );
      final city = nearestCity(pos.latitude, pos.longitude);
      await _prefs.setPrayerLocation(pos.latitude, pos.longitude, placeAr: city?.ar, placeEn: city?.en);
      notifyListeners();
      return LocateResult.ok;
    } catch (e) {
      debugPrint('locate failed: $e');
      return LocateResult.failed;
    }
  }

  Future<void> setCity(City c) async {
    await _prefs.setPrayerLocation(c.lat, c.lng, placeAr: c.ar, placeEn: c.en);
    notifyListeners();
  }

  Future<void> setMethod(PrayerMethodId? m) async {
    await _prefs.setPrayerMethod(m?.name);
    notifyListeners();
  }

  Future<void> setAsrHanafi(bool v) async {
    await _prefs.setAsrHanafi(v);
    notifyListeners();
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
}
