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
      final days = reminder > 0 ? 6 : 7;
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
