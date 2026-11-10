import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../services/prefs.dart';
import 'prayer_controller.dart';
import 'prayer_times.dart';

/// تنبيهات مواقيت الصلاة: بتتجدول على الجهاز (من غير سيرفر)، بصوت الإشعار العادي.
/// بنجدول كام يوم لقدام، وبنجدد كل ما التطبيق يتفتح أو الإعدادات تتغير.
class PrayerAlerts {
  PrayerAlerts._();

  static final PrayerAlerts instance = PrayerAlerts._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // أرقام الإشعارات بتاعتنا من ٥٠٠٠ لـ٥٩٩٩، عشان منلمسش إشعارات تانية.
  static const _base = 5000;
  static const _maxIds = 1000;

  static const _prayers = [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  /// طلب إذن الإشعارات (أندرويد ١٣+ والآيفون). بيرجع true لو اتسمح.
  Future<bool> requestPermission() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<void> _cancelOurs() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _base && p.id < _base + _maxIds) await _plugin.cancel(p.id);
    }
  }

  /// بيلغي القديم ويجدول من جديد حسب الإعدادات الحالية.
  Future<void> reschedule() async {
    await rescheduleReminders();
    try {
      await _init();
      await _cancelOurs();
      final prefs = Prefs.instance;
      final c = PrayerController.instance;
      if (!prefs.prayerAlerts || !c.hasLocation) return;

      final ar = prefs.locale.languageCode != 'en';
      final enabled = prefs.prayerAlertsFor;
      final reminder = prefs.prayerReminderMinutes;
      // الآيفون بيسمح بـ٦٤ إشعار مجدول بس.
      // (وبنسيب مكان للتذكيرات التانية: الأذكار والورد والجمعة.)
      final days = reminder > 0 ? 5 : 7;
      final now = DateTime.now();
      final place = c.placeName(ar ? 'ar' : 'en');

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'prayer_times',
          'مواقيت الصلاة',
          channelDescription: 'تنبيه هادي وقت كل صلاة',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      );

      var id = _base;
      for (var d = 0; d < days; d++) {
        final day = DateTime(now.year, now.month, now.day + d);
        final times = c.timesFor(day);
        for (final p in _prayers) {
          if (!enabled.contains(p.name)) continue;
          final at = times[p];
          final name = _name(p, ar);
          final where = place == null ? '' : (ar ? ' في $place' : ' in $place');
          await _schedule(id++, at, ar ? 'حان الآن موعد صلاة $name' : 'It\'s time for $name', ar ? 'تقبّل الله$where' : 'May Allah accept it$where', details);
          if (reminder > 0) {
            await _schedule(
              id++,
              at.subtract(Duration(minutes: reminder)),
              ar ? 'صلاة $name بعد $reminder دقيقة' : '$name in $reminder minutes',
              ar ? 'استعد للصلاة' : 'Get ready for prayer',
              details,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('prayer alerts failed: $e');
    }
  }

  // ---------- تذكيرات الأذكار والورد والجمعة ----------
  // أرقامها من ٦٠٠٠. اليومي والأسبوعي إشعار واحد بيتكرر، والورد إشعار لكل يوم عشان نقدر نشيل بتاع النهارده لو قريت.

  static const _remBase = 6000;
  static const _wardDays = 5;

  /// [readToday]: قريت النهارده، فتذكير الورد بتاع النهارده مش هييجي.
  Future<void> rescheduleReminders({bool? readToday}) async {
    try {
      await _init();
      final prefs = Prefs.instance;
      final ar = prefs.locale.languageCode != 'en';
      const details = NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'تذكيرات', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentSound: true),
      );
      final now = DateTime.now();
      DateTime at(String key, int dayOffset) {
        final m = prefs.reminderMinutes(key);
        return DateTime(now.year, now.month, now.day + dayOffset, m ~/ 60, m % 60);
      }

      // يومي بيتكرر.
      const daily = {
        'adhkarMorning': (1, 'أذكار الصباح', 'Morning adhkar', 'ابدأ يومك بذكر الله', 'Start your day with dhikr'),
        'adhkarEvening': (2, 'أذكار المساء', 'Evening adhkar', 'وقت أذكار المساء', 'Time for the evening adhkar'),
        'adhkarSleep': (3, 'أذكار النوم', 'Sleep adhkar', 'قبل ما تنام، اقرا أذكار النوم', 'Read the sleep adhkar before bed'),
      };
      for (final e in daily.entries) {
        final (n, tAr, tEn, bAr, bEn) = e.value;
        await _plugin.cancel(_remBase + n);
        if (!prefs.reminderOn(e.key)) continue;
        var first = at(e.key, 0);
        if (!first.isAfter(now)) first = at(e.key, 1);
        await _repeat(_remBase + n, first, ar ? tAr : tEn, ar ? bAr : bEn, details, DateTimeComponents.time);
      }

      // الجمعة، أسبوعي.
      const friday = {
        'kahf': (4, 'سورة الكهف', 'Surah Al-Kahf', 'النهارده الجمعة، متنساش سورة الكهف', 'It\'s Friday: read Surah Al-Kahf'),
        'salawat': (5, 'الصلاة على النبي ﷺ', 'Salawat upon the Prophet ﷺ', 'أكثروا من الصلاة عليه يوم الجمعة', 'Send plenty of salawat on Friday'),
      };
      for (final e in friday.entries) {
        final (n, tAr, tEn, bAr, bEn) = e.value;
        await _plugin.cancel(_remBase + n);
        if (!prefs.reminderOn(e.key)) continue;
        var offset = (DateTime.friday - now.weekday) % 7;
        if (offset == 0 && !at(e.key, 0).isAfter(now)) offset = 7;
        await _repeat(_remBase + n, at(e.key, offset), ar ? tAr : tEn, ar ? bAr : bEn, details, DateTimeComponents.dayOfWeekAndTime);
      }

      // الورد: لكل يوم لوحده.
      for (var d = 0; d < _wardDays; d++) {
        await _plugin.cancel(_remBase + 10 + d);
      }
      if (prefs.reminderOn('ward')) {
        final read = readToday ?? ((prefs.readingSeconds[_dayKey(now)] ?? 0) >= 60);
        var id = _remBase + 10;
        for (var d = 0; d < _wardDays + 1 && id < _remBase + 10 + _wardDays; d++) {
          if (d == 0 && read) continue;
          final when = at('ward', d);
          if (!when.isAfter(now)) continue;
          await _schedule(id++, when, ar ? 'وردك النهارده' : 'Your reading today', ar ? 'لسه مقريتش النهارده، افتح المصحف وكمّل وردك' : 'You haven\'t read today yet. Open the Mushaf and continue.', details);
        }
      }
    } catch (e) {
      debugPrint('reminders failed: $e');
    }
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _repeat(int id, DateTime local, String title, String body, NotificationDetails details, DateTimeComponents match) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(local.toUtc(), tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match,
    );
  }

  /// تنبيه واحد في ميعاد (زي تذكير الحول). أرقامه برا رينج الصلاة.
  Future<void> scheduleOne(int id, DateTime at, String title, String body) async {
    try {
      await _init();
      await _plugin.cancel(id);
      const details = NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'تذكيرات', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentSound: true),
      );
      await _schedule(id, at, title, body, details);
    } catch (e) {
      debugPrint('reminder failed: $e');
    }
  }

  Future<void> cancelOne(int id) async {
    try {
      await _init();
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> _schedule(int id, DateTime utc, String title, String body, NotificationDetails details) async {
    if (!utc.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(utc.toUtc(), tz.UTC),
      details,
      // من غير "تنبيه دقيق": أندرويد ممكن يأخره دقايق بسيطة عشان البطارية.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static String _name(Prayer p, bool ar) => switch (p) {
        Prayer.fajr => ar ? 'الفجر' : 'Fajr',
        Prayer.sunrise => ar ? 'الشروق' : 'Sunrise',
        Prayer.dhuhr => ar ? 'الظهر' : 'Dhuhr',
        Prayer.asr => ar ? 'العصر' : 'Asr',
        Prayer.maghrib => ar ? 'المغرب' : 'Maghrib',
        Prayer.isha => ar ? 'العشاء' : 'Isha',
      };
}
