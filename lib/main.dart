import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'features/prayer/prayer_alerts.dart';
import 'features/prayer/prayer_controller.dart';
import 'firebase_options.dart';
import 'l10n/gen/app_localizations.dart';
import 'services/auth_service.dart';
import 'services/groups_service.dart';
import 'services/home_widgets.dart';
import 'services/prefs.dart';
import 'services/push_service.dart';
import 'services/reading_time.dart';
import 'services/update_service.dart';
import 'services/personal_ward.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Prefs.init();
  localeNotifier.value = Prefs.instance.locale;
  themeModeNotifier.value = Prefs.instance.themeMode;
  // الإشعارات بتبدأ بعد تسجيل الدخول، وبتقف بعد الخروج.
  void syncPush() {
    if (AuthService.instance.isSignedIn) {
      PushService.instance.start();
    } else {
      PushService.instance.stop();
    }
  }

  AuthService.instance.addListener(syncPush);
  syncPush();
  // القراءة اللي اتسجلت من غير نت: بتتبعت لوحدها لما النت يرجع، وبتظهر رسالة بالنتيجة.
  GroupsService.instance.onSyncNotice = (notice, points) {
    final ctx = rootMessenger.currentContext;
    if (ctx == null) return;
    final t = AppLocalizations.of(ctx);
    final text = switch (notice) {
      SyncNotice.synced => points > 0 ? t.offlineSyncedPoints(points) : t.offlineSynced,
      SyncNotice.late => t.offlineSyncedLate,
      SyncNotice.taken => t.offlineTaken,
      SyncNotice.failed => t.offlineFailed,
    };
    rootMessenger.currentState?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
  };
  GroupsService.instance.startSync();
  AuthService.instance.addListener(GroupsService.instance.flushPending);
  // تنبيهات الصلاة: بتتجدد مع كل فتح للتطبيق، ولما المكان أو الإعدادات تتغير.
  PrayerController.instance.addListener(PrayerAlerts.instance.reschedule);
  PrayerAlerts.instance.reschedule();
  HomeWidgets.instance.start();
  ReadingTime.instance.onReadToday = () => PrayerAlerts.instance.rescheduleReminders();
  // الورد الشخصي اتغير: التذكيرات تتجدد (بعد ثانيتين، عشان التعديلات ورا بعض تبقى مرة واحدة).
  Timer? personalTimer;
  PersonalWard.instance.onScheduleChanged = () {
    personalTimer?.cancel();
    personalTimer = Timer(const Duration(seconds: 2), PrayerAlerts.instance.reschedule);
  };
  // مقارنة النسخة بآخر نسخة، وتسجيلها في حساب المستخدم.
  UpdateService.instance.start();
  runApp(const TaawanuApp());
}
