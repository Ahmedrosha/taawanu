import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../router.dart';
import 'prefs.dart';
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

      // لو قافل إشعارات المجموعات من الإعدادات، الجهاز مبيتسجلش.
      if (Prefs.instance.groupPush) {
        final token = await messaging.getToken();
        if (token != null) await UserService.instance.addFcmToken(token);
        _tokenSub = messaging.onTokenRefresh.listen(UserService.instance.addFcmToken);
      }

      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      // الإشعارات مش أساسية لتشغيل التطبيق (مثلًا على محاكي من غير Google Play).
      debugPrint('Push setup failed: $e');
    }
  }

  /// تشغيل أو قفل إشعارات المجموعات والرسائل على الجهاز ده.
  Future<void> setEnabled(bool on) async {
    await Prefs.instance.setGroupPush(on);
    try {
      final messaging = FirebaseMessaging.instance;
      if (on) {
        await messaging.requestPermission();
        final token = await messaging.getToken();
        if (token != null) await UserService.instance.addFcmToken(token);
        _tokenSub ??= messaging.onTokenRefresh.listen(UserService.instance.addFcmToken);
      } else {
        await _tokenSub?.cancel();
        _tokenSub = null;
        final token = await messaging.getToken();
        if (token != null) await UserService.instance.removeFcmToken(token);
      }
    } catch (e) {
      debugPrint('Push toggle failed: $e');
    }
  }

  void stop() {
    _tokenSub?.cancel();
    _tokenSub = null;
    _started = false;
  }

  void _open(RemoteMessage message) {
    // الرسائل بتفتح قسم الرسائل.
    final type = message.data['type'];
    if (type == 'message' || type == 'reminder') {
      appRouter.push('/messages');
      return;
    }
    final groupId = message.data['groupId'];
    if (groupId is String && groupId.isNotEmpty) {
      appRouter.push('/group/$groupId');
    }
  }
}
