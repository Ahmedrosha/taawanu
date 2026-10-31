import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../l10n/gen/app_localizations.dart';

/// بيحوّل خطأ تسجيل الدخول لرسالة مفهومة + كود قصير،
/// عشان لو حد بعتلنا صورة الرسالة نعرف السبب على طول.
String signInErrorText(AppLocalizations t, Object e) {
  String withCode(String msg, String code) => '$msg\n${t.errorCode(code)}';

  if (e is SocketException) return withCode(t.signInNoInternet, 'network');

  if (e is GoogleSignInException) {
    final code = e.code.name;
    final desc = (e.description ?? '').toLowerCase();
    if (desc.contains('no credential')) return withCode(t.signInNoGoogleAccount, 'gsi-$code');
    if (code == 'clientConfigurationError' || code == 'providerConfigurationError') {
      return withCode(t.signInConfigError, 'gsi-$code');
    }
    return withCode(t.signInFailed, 'gsi-$code');
  }

  if (e is FirebaseAuthException) {
    final code = e.code;
    switch (code) {
      case 'network-request-failed':
        return withCode(t.signInNoInternet, 'auth-$code');
      case 'admin-restricted-operation':
      case 'operation-not-allowed':
        return withCode(t.signInSignupClosed, 'auth-$code');
      case 'user-disabled':
        return withCode(t.signInAccountDisabled, 'auth-$code');
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return withCode(t.signInWrongCredentials, 'auth-$code');
      case 'too-many-requests':
        return withCode(t.signInTooMany, 'auth-$code');
      default:
        return withCode(t.signInFailed, 'auth-$code');
    }
  }

  // أخطاء Firestore وقت إنشاء ملف المستخدم أول مرة.
  if (e is FirebaseException) {
    if (e.code == 'unavailable') return withCode(t.signInNoInternet, '${e.plugin}-${e.code}');
    return withCode(t.signInFailed, '${e.plugin}-${e.code}');
  }

  return withCode(t.signInFailed, e.runtimeType.toString());
}
