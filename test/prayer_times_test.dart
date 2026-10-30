import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/features/prayer/prayer_times.dart';

/// الوقت بتوقيت المكان (فرق ثابت عن UTC) بالدقايق من نص الليل.
int localMinutes(DateTime utc, int tzHours) {
  final l = utc.add(Duration(hours: tzHours));
  return l.hour * 60 + l.minute;
}

int hm(int h, int m) => h * 60 + m;

void main() {
  group('مواقيت الصلاة', () {
    test('لندن ٣١ أكتوبر ٢٠٢٦: الشروق والغروب قريبين من الجداول الفلكية', () {
      final d = computePrayerTimes(date: DateTime(2026, 10, 31), lat: 51.5074, lng: -0.1278, method: PrayerMethodId.mwl);
      expect(localMinutes(d[Prayer.sunrise], 0), closeTo(hm(6, 52), 3));
      expect(localMinutes(d[Prayer.maghrib], 0), closeTo(hm(16, 35), 3));
    });

    test('دبي: الترتيب صحيح والظهر قريب من ١٢:٠٣', () {
      final d = computePrayerTimes(date: DateTime(2026, 10, 31), lat: 25.2048, lng: 55.2708, method: PrayerMethodId.gulf);
      final order = [Prayer.fajr, Prayer.sunrise, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];
      for (var i = 1; i < order.length; i++) {
        expect(d[order[i]].isAfter(d[order[i - 1]]), isTrue, reason: '${order[i]} after ${order[i - 1]}');
      }
      expect(localMinutes(d[Prayer.dhuhr], 4), closeTo(hm(12, 3), 2));
      expect(localMinutes(d[Prayer.fajr], 4), closeTo(hm(5, 7), 3));
    });

    test('أم القرى: العشاء بعد المغرب بـ٩٠ دقيقة', () {
      final d = computePrayerTimes(date: DateTime(2026, 10, 31), lat: 21.4225, lng: 39.8262, method: PrayerMethodId.ummAlQura);
      expect(d[Prayer.isha].difference(d[Prayer.maghrib]).inMinutes, 90);
    });

    test('العصر الحنفي بعد العصر العادي', () {
      final a = computePrayerTimes(date: DateTime(2026, 10, 31), lat: 30.0444, lng: 31.2357, method: PrayerMethodId.egypt);
      final h = computePrayerTimes(date: DateTime(2026, 10, 31), lat: 30.0444, lng: 31.2357, method: PrayerMethodId.egypt, asrHanafi: true);
      expect(h[Prayer.asr].isAfter(a[Prayer.asr]), isTrue);
    });

    test('خطوط العرض العالية في الصيف: مفيش أوقات فاضية', () {
      final d = computePrayerTimes(date: DateTime(2026, 6, 21), lat: 59.33, lng: 18.06, method: PrayerMethodId.mwl);
      expect(d[Prayer.fajr].isBefore(d[Prayer.sunrise]), isTrue);
      expect(d[Prayer.isha].isAfter(d[Prayer.maghrib]), isTrue);
    });
  });

  group('الطريقة حسب المكان', () {
    test('بلاد معروفة', () {
      expect(defaultMethodFor(25.2, 55.27), PrayerMethodId.gulf);
      expect(defaultMethodFor(24.71, 46.67), PrayerMethodId.ummAlQura);
      expect(defaultMethodFor(30.04, 31.23), PrayerMethodId.egypt);
      expect(defaultMethodFor(25.28, 51.53), PrayerMethodId.qatar);
      expect(defaultMethodFor(29.37, 47.97), PrayerMethodId.kuwait);
      expect(defaultMethodFor(41.0, 28.97), PrayerMethodId.turkey);
      expect(defaultMethodFor(40.71, -74.0), PrayerMethodId.isna);
      expect(defaultMethodFor(51.5, -0.12), PrayerMethodId.mwl);
    });
  });

  group('القبلة', () {
    test('اتجاهات معروفة', () {
      expect(qiblaBearing(51.5074, -0.1278), closeTo(118.99, 0.5)); // لندن
      expect(qiblaBearing(30.0444, 31.2357), closeTo(136.1, 0.5)); // القاهرة
    });
    test('المسافة لمكة', () {
      expect(distanceToKaabaKm(30.0444, 31.2357), closeTo(1280, 30));
    });
    test('أقرب مدينة', () {
      expect(nearestCity(25.1, 55.2)?.en, 'Dubai');
      expect(nearestCity(0, 0), isNull);
    });
  });
}
