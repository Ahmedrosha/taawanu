import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

/// معرّف عميل الويب من google-services.json (client_type 3).
/// أندرويد محتاجه عشان يطلب idToken يقدر Firebase يتحقق منه.
const _googleServerClientId =
    '880661928235-5km2p3tfl3tqd3j0udp4fu868iv9v3ig.apps.googleusercontent.com';

/// تسجيل الدخول والخروج، وإنشاء ملف المستخدم أول مرة.
class AuthService extends ChangeNotifier {
  AuthService._() {
    _sub = _auth.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
    _user = _auth.currentUser;
  }

  static final AuthService instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  late final StreamSubscription<User?> _sub;
  User? _user;
  bool _googleReady = false;

  User? get user => _user;
  bool get isSignedIn => _user != null;

  /// زرار Apple بيظهر على الآيفون بس دلوقتي.
  bool get appleAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? DefaultFirebaseOptions.ios.iosClientId
          : null,
      serverClientId: _googleServerClientId,
    );
    _googleReady = true;
  }

  /// بيرجع false لو المستخدم لغى بنفسه، وبيرمي خطأ لو حصلت مشكلة.
  Future<bool> signInWithGoogle({required String locale, required String fallbackName}) async {
    await _ensureGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    await _ensureProfile(result.user!, locale: locale, fallbackName: fallbackName);
    return true;
  }

  Future<bool> signInWithApple({required String locale, required String fallbackName}) async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    try {
      final result = await _auth.signInWithProvider(provider);
      await _ensureProfile(result.user!, locale: locale, fallbackName: fallbackName);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled') return false;
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (_googleReady) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }

  /// أول دخول: بنعمل ملف المستخدم بالحقول اللي قواعد الأمان بتسمح بيها بس.
  Future<void> _ensureProfile(User user, {required String locale, required String fallbackName}) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;

    var name = (user.displayName ?? '').trim();
    if (name.isEmpty) name = fallbackName;
    if (name.length > 60) name = name.substring(0, 60);

    await ref.set({
      'name': name,
      if (user.photoURL != null) 'photoUrl': user.photoURL,
      'locale': locale,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
