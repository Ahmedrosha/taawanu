import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'prefs.dart';

enum UpdateNeed { none, optional, required }

/// بيقارن نسخة التطبيق بآخر نسخة وأقل نسخة مسموحة (config/app على السيرفر)،
/// وبيسجّل نسخة التطبيق في حساب المستخدم عشان نعرف كام واحد محدّث.
class UpdateService with WidgetsBindingObserver {
  UpdateService._();
  static final instance = UpdateService._();

  static const appStoreUrl = 'https://apps.apple.com/app/id6828872604';
  static const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.taawanu.taawanu';

  final need = ValueNotifier<UpdateNeed>(UpdateNeed.none);
  String version = '';
  String latest = '';
  bool _started = false;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void start() {
    if (_started || !(_android || _ios)) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.authStateChanges().listen((_) => _record());
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  /// مقارنة أرقام النسخ: 1.0.17 أقل من 1.0.18 وأقل من 1.1.0.
  static int compare(String a, String b) {
    List<int> parts(String v) => v.split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  Future<void> check() async {
    try {
      version = version.isNotEmpty ? version : (await PackageInfo.fromPlatform()).version;
      final snap = await FirebaseFirestore.instance.collection('config').doc('app').get();
      final d = snap.data() ?? const {};
      final p = _android ? 'Android' : 'Ios';
      latest = (d['latest$p'] as String?) ?? '';
      final min = (d['min$p'] as String?) ?? '';
      if (min.isNotEmpty && compare(version, min) < 0) {
        need.value = UpdateNeed.required;
      } else if (latest.isNotEmpty && compare(version, latest) < 0) {
        need.value = UpdateNeed.optional;
      } else {
        need.value = UpdateNeed.none;
      }
    } catch (_) {
      // من غير نت أو السيرفر مش متاح: التطبيق يكمل عادي.
    }
    _record();
  }

  /// شريط التحديث اتقفل؟ بيرجع بعد يوم، أو لو نزلت نسخة أحدث.
  bool get bannerDismissed {
    final at = Prefs.instance.updateDismissedAt;
    return Prefs.instance.updateDismissedFor == latest && at != null && DateTime.now().difference(at).inHours < 24;
  }

  Future<void> dismissBanner() async {
    await Prefs.instance.setUpdateDismissed(latest);
    need.value = UpdateNeed.none;
    need.value = UpdateNeed.optional; // يعيد بناء اللي بيسمع
  }

  /// زرار التحديث: في أندرويد بيحاول التحديث من جوه التطبيق، وإلا بيفتح صفحة المتجر.
  Future<void> update() async {
    if (_android) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          if (info.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
            return;
          }
          if (info.flexibleUpdateAllowed) {
            await InAppUpdate.startFlexibleUpdate();
            await InAppUpdate.completeFlexibleUpdate();
            return;
          }
        }
      } catch (_) {
        // مثلًا متسطب من برا جوجل بلاي: نفتح المتجر.
      }
    }
    await launchUrl(Uri.parse(_android ? playStoreUrl : appStoreUrl), mode: LaunchMode.externalApplication);
  }

  /// بيسجّل النسخة في حساب المستخدم مرة لكل نسخة (مش مع كل فتح).
  Future<void> _record() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || version.isEmpty) return;
    final key = '${user.uid}|$version';
    if (Prefs.instance.recordedVersion == key) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'appVersion': version,
        'appPlatform': _android ? 'android' : 'ios',
        'appVersionAt': FieldValue.serverTimestamp(),
      });
      await Prefs.instance.setRecordedVersion(key);
    } catch (_) {}
  }
}
