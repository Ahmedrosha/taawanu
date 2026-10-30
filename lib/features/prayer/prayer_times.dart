import 'dart:math' as math;

/// حساب مواقيت الصلاة على الجهاز (من غير إنترنت)، بنفس خوارزمية PrayTimes المعروفة.
/// كل الدوال هنا صافية، عشان نختبرها.

enum PrayerMethodId { ummAlQura, egypt, gulf, kuwait, qatar, mwl, karachi, isna, turkey, singapore }

class PrayerMethod {
  const PrayerMethod(this.id, {required this.fajrAngle, this.ishaAngle, this.ishaMinutes});

  final PrayerMethodId id;
  final double fajrAngle;
  final double? ishaAngle;

  /// بعض الطرق العشاء فيها بعد المغرب بعدد دقايق ثابت (أم القرى وقطر).
  final int? ishaMinutes;
}

const prayerMethods = <PrayerMethodId, PrayerMethod>{
  PrayerMethodId.ummAlQura: PrayerMethod(PrayerMethodId.ummAlQura, fajrAngle: 18.5, ishaMinutes: 90),
  PrayerMethodId.egypt: PrayerMethod(PrayerMethodId.egypt, fajrAngle: 19.5, ishaAngle: 17.5),
  PrayerMethodId.gulf: PrayerMethod(PrayerMethodId.gulf, fajrAngle: 18.2, ishaAngle: 18.2),
  PrayerMethodId.kuwait: PrayerMethod(PrayerMethodId.kuwait, fajrAngle: 18, ishaAngle: 17.5),
  PrayerMethodId.qatar: PrayerMethod(PrayerMethodId.qatar, fajrAngle: 18, ishaMinutes: 90),
  PrayerMethodId.mwl: PrayerMethod(PrayerMethodId.mwl, fajrAngle: 18, ishaAngle: 17),
  PrayerMethodId.karachi: PrayerMethod(PrayerMethodId.karachi, fajrAngle: 18, ishaAngle: 18),
  PrayerMethodId.isna: PrayerMethod(PrayerMethodId.isna, fajrAngle: 15, ishaAngle: 15),
  PrayerMethodId.turkey: PrayerMethod(PrayerMethodId.turkey, fajrAngle: 18, ishaAngle: 17),
  PrayerMethodId.singapore: PrayerMethod(PrayerMethodId.singapore, fajrAngle: 20, ishaAngle: 18),
};

enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

class PrayerDay {
  const PrayerDay(this.times);

  /// المواقيت بتوقيت UTC.
  final Map<Prayer, DateTime> times;

  DateTime operator [](Prayer p) => times[p]!;
}

/// الطريقة الافتراضية حسب المكان (تقريبي بحدود البلاد).
PrayerMethodId defaultMethodFor(double lat, double lng) {
  bool box(double la1, double la2, double lo1, double lo2) => lat >= la1 && lat <= la2 && lng >= lo1 && lng <= lo2;
  if (box(24.4, 26.2, 50.7, 51.7)) return PrayerMethodId.qatar; // قبل الإمارات لأن حدودهم قريبة
  if (box(22.5, 26.5, 51.5, 56.5)) return PrayerMethodId.gulf; // الإمارات
  if (box(28.5, 30.1, 46.5, 48.5)) return PrayerMethodId.kuwait;
  if (box(16, 32.2, 34.5, 55.7)) return PrayerMethodId.ummAlQura; // السعودية وما حولها
  if (box(22, 31.7, 24.7, 35)) return PrayerMethodId.egypt;
  if (box(-35, 37.5, -18, 34.9) || box(-12, 18, 34, 52)) return PrayerMethodId.egypt; // أفريقيا
  if (box(36, 42.2, 26, 45)) return PrayerMethodId.turkey;
  if (box(5, 38, 60, 93)) return PrayerMethodId.karachi;
  if (box(-11, 7.5, 95, 141)) return PrayerMethodId.singapore;
  if (box(15, 72, -170, -50)) return PrayerMethodId.isna;
  return PrayerMethodId.mwl;
}

// ---------- حسابات فلكية ----------

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
double _fix(double a, double b) {
  final x = a - b * (a / b).floor();
  return x < 0 ? x + b : x;
}

double _fixAngle(double a) => _fix(a, 360);
double _fixHour(double a) => _fix(a, 24);

double _julian(int y, int m, int d) {
  if (m <= 2) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + b - 1524.5;
}

/// (الميل الشمسي، معادلة الزمن)
(double, double) _sun(double jd) {
  final dd = jd - 2451545.0;
  final g = _fixAngle(357.529 + 0.98560028 * dd);
  final q = _fixAngle(280.459 + 0.98564736 * dd);
  final l = _fixAngle(q + 1.915 * math.sin(_rad(g)) + 0.020 * math.sin(_rad(2 * g)));
  final e = 23.439 - 0.00000036 * dd;
  final ra = _deg(math.atan2(math.cos(_rad(e)) * math.sin(_rad(l)), math.cos(_rad(l)))) / 15;
  final eqt = q / 15 - _fixHour(ra);
  final decl = _deg(math.asin(math.sin(_rad(e)) * math.sin(_rad(l))));
  return (decl, eqt);
}

/// مواقيت يوم معين لمكان معين. [asrHanafi]: ظل المثلين.
PrayerDay computePrayerTimes({
  required DateTime date,
  required double lat,
  required double lng,
  required PrayerMethodId method,
  bool asrHanafi = false,
  bool ramadan = false,
}) {
  final m = prayerMethods[method]!;
  final jd = _julian(date.year, date.month, date.day) - lng / (15 * 24);

  double midDay(double t) => _fixHour(12 - _sun(jd + t).$2);

  double sunAngleTime(double angle, double t, {bool ccw = false}) {
    final decl = _sun(jd + t).$1;
    final noon = midDay(t);
    final c = (-math.sin(_rad(angle)) - math.sin(_rad(decl)) * math.sin(_rad(lat))) /
        (math.cos(_rad(decl)) * math.cos(_rad(lat)));
    if (c < -1 || c > 1) return double.nan; // خطوط العرض العالية
    final tt = _deg(math.acos(c)) / 15;
    return noon + (ccw ? -tt : tt);
  }

  double asrTime(double factor, double t) {
    final decl = _sun(jd + t).$1;
    final angle = -_deg(math.atan(1 / (factor + math.tan(_rad((lat - decl).abs())))));
    return sunAngleTime(angle, t);
  }

  // تقدير أولي ثم حساب واحد بالقيم دي (زي PrayTimes).
  const riseSet = 0.833;
  var fajr = sunAngleTime(m.fajrAngle, 5 / 24, ccw: true);
  final sunrise = sunAngleTime(riseSet, 6 / 24, ccw: true);
  final dhuhr = midDay(12 / 24);
  final asr = asrTime(asrHanafi ? 2 : 1, 13 / 24);
  final sunset = sunAngleTime(riseSet, 18 / 24);
  // أم القرى: العشاء بعد المغرب بساعتين في رمضان بدل ساعة ونص.
  final ishaMinutes = m.ishaMinutes == null ? null : (ramadan && method == PrayerMethodId.ummAlQura ? 120 : m.ishaMinutes!);
  var isha = ishaMinutes != null ? sunset + ishaMinutes / 60 : sunAngleTime(m.ishaAngle!, 18 / 24);

  // خطوط العرض العالية: طريقة الزاوية (جزء من الليل).
  final night = _fixHour(sunrise - sunset);
  final fajrPortion = m.fajrAngle / 60 * night;
  if (fajr.isNaN || _fixHour(sunrise - fajr) > fajrPortion) fajr = sunrise - fajrPortion;
  if (m.ishaMinutes == null) {
    final ishaPortion = m.ishaAngle! / 60 * night;
    if (isha.isNaN || _fixHour(isha - sunset) > ishaPortion) isha = sunset + ishaPortion;
  }

  final base = DateTime.utc(date.year, date.month, date.day);
  DateTime at(double hoursLocalSolar) {
    // من التوقيت الشمسي المحلي لـUTC، وتقريب لأقرب دقيقة.
    final minutes = ((hoursLocalSolar - lng / 15) * 60).round();
    return base.add(Duration(minutes: minutes));
  }

  return PrayerDay({
    Prayer.fajr: at(fajr),
    Prayer.sunrise: at(sunrise),
    Prayer.dhuhr: at(dhuhr),
    Prayer.asr: at(asr),
    Prayer.maghrib: at(sunset),
    Prayer.isha: at(isha),
  });
}

// ---------- القبلة ----------

const kaabaLat = 21.4225;
const kaabaLng = 39.8262;

/// اتجاه القبلة بالدرجات من الشمال الحقيقي (مع عقارب الساعة).
double qiblaBearing(double lat, double lng) {
  final p1 = _rad(lat), p2 = _rad(kaabaLat), dl = _rad(kaabaLng - lng);
  final y = math.sin(dl);
  final x = math.cos(p1) * math.tan(p2) - math.sin(p1) * math.cos(dl);
  return _fixAngle(_deg(math.atan2(y, x)));
}

/// المسافة لمكة بالكيلومتر.
double distanceToKaabaKm(double lat, double lng) => distanceKm(lat, lng, kaabaLat, kaabaLng);

double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final dp = _rad(lat2 - lat1), dl = _rad(lng2 - lng1);
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

// ---------- مدن للاختيار اليدوي ----------

class City {
  const City(this.ar, this.en, this.lat, this.lng);
  final String ar;
  final String en;
  final double lat;
  final double lng;
}

const cities = <City>[
  City('دبي', 'Dubai', 25.2048, 55.2708),
  City('أبوظبي', 'Abu Dhabi', 24.4539, 54.3773),
  City('الشارقة', 'Sharjah', 25.3463, 55.4209),
  City('العين', 'Al Ain', 24.2075, 55.7447),
  City('مكة المكرمة', 'Makkah', 21.4225, 39.8262),
  City('المدينة المنورة', 'Madinah', 24.4672, 39.6111),
  City('الرياض', 'Riyadh', 24.7136, 46.6753),
  City('جدة', 'Jeddah', 21.4858, 39.1925),
  City('الدمام', 'Dammam', 26.4207, 50.0888),
  City('الكويت', 'Kuwait City', 29.3759, 47.9774),
  City('الدوحة', 'Doha', 25.2854, 51.5310),
  City('المنامة', 'Manama', 26.2285, 50.5860),
  City('مسقط', 'Muscat', 23.5880, 58.3829),
  City('القاهرة', 'Cairo', 30.0444, 31.2357),
  City('الإسكندرية', 'Alexandria', 31.2001, 29.9187),
  City('المنصورة', 'Mansoura', 31.0409, 31.3785),
  City('طنطا', 'Tanta', 30.7865, 31.0004),
  City('أسيوط', 'Assiut', 27.1783, 31.1859),
  City('الأقصر', 'Luxor', 25.6872, 32.6396),
  City('أسوان', 'Aswan', 24.0889, 32.8998),
  City('عمّان', 'Amman', 31.9454, 35.9284),
  City('القدس', 'Jerusalem', 31.7683, 35.2137),
  City('غزة', 'Gaza', 31.5017, 34.4668),
  City('بيروت', 'Beirut', 33.8938, 35.5018),
  City('دمشق', 'Damascus', 33.5138, 36.2765),
  City('بغداد', 'Baghdad', 33.3152, 44.3661),
  City('صنعاء', 'Sanaa', 15.3694, 44.1910),
  City('الخرطوم', 'Khartoum', 15.5007, 32.5599),
  City('طرابلس', 'Tripoli', 32.8872, 13.1913),
  City('تونس', 'Tunis', 36.8065, 10.1815),
  City('الجزائر', 'Algiers', 36.7538, 3.0588),
  City('الدار البيضاء', 'Casablanca', 33.5731, -7.5898),
  City('الرباط', 'Rabat', 34.0209, -6.8416),
  City('إسطنبول', 'Istanbul', 41.0082, 28.9784),
  City('كراتشي', 'Karachi', 24.8607, 67.0011),
  City('كوالالمبور', 'Kuala Lumpur', 3.1390, 101.6869),
  City('جاكرتا', 'Jakarta', -6.2088, 106.8456),
  City('لندن', 'London', 51.5074, -0.1278),
  City('باريس', 'Paris', 48.8566, 2.3522),
  City('برلين', 'Berlin', 52.5200, 13.4050),
  City('نيويورك', 'New York', 40.7128, -74.0060),
  City('تورنتو', 'Toronto', 43.6532, -79.3832),
];

/// أقرب مدينة من القائمة (لعرض اسم المكان بعد تحديد الموقع)، لو أقرب من [maxKm].
City? nearestCity(double lat, double lng, {double maxKm = 60}) {
  City? best;
  var bestD = double.infinity;
  for (final c in cities) {
    final d = distanceKm(lat, lng, c.lat, c.lng);
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return bestD <= maxKm ? best : null;
}
