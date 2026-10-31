import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/prefs.dart';
import 'services/push_service.dart';

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
  runApp(const TaawanuApp());
}
