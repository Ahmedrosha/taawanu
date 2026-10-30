import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../router.dart';
import 'user_service.dart';

/// الإشعارات: الإذن، وتسجيل الجهاز، وفتح المجموعة لما المستخدم يضغط على الإشعار.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _started = false;
  StreamSubscription<String>? _tokenSub;

  /// بيتنده بعد تسجيل الدخول.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await UserService.instance.addFcmToken(token);
      _tokenSub = messaging.onTokenRefresh.listen(UserService.instance.addFcmToken);

      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      // الإشعارات مش أساسية لتشغيل التطبيق (مثلًا على محاكي من غير Google Play).
      debugPrint('Push setup failed: $e');
    }
  }

  void stop() {
    _tokenSub?.cancel();
    _tokenSub = null;
    _started = false;
  }

  void _open(RemoteMessage message) {
    final groupId = message.data['groupId'];
    if (groupId is String && groupId.isNotEmpty) {
      appRouter.push('/group/$groupId');
    }
  }
}
