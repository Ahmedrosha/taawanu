import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// إحصائيات المستخدم (السيرفر بس هو اللي بيكتبها).
class UserStats {
  const UserStats({
    required this.name,
    required this.points,
    required this.streak,
    required this.longestStreak,
    required this.quartersRead,
    required this.onTimeCycles,
    required this.totalCycles,
    required this.khatmasGroup,
    required this.khatmasPersonal,
    required this.badges,
  });

  final String name;
  final int points;
  final int streak;
  final int longestStreak;
  final int quartersRead;
  final int onTimeCycles;
  final int totalCycles;
  final int khatmasGroup;
  final int khatmasPersonal;
  final Set<String> badges;

  /// نسبة الالتزام (٠–١٠٠)، أو null لو لسه مفيش دورات.
  int? get commitment => totalCycles == 0 ? null : (onTimeCycles * 100 / totalCycles).round();

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  factory UserStats.fromMap(Map<String, dynamic>? d) {
    d ??= const {};
    return UserStats(
      name: (d['name'] as String?) ?? '',
      points: _i(d['points']),
      streak: _i(d['streak']),
      longestStreak: _i(d['longestStreak']),
      quartersRead: _i(d['quartersRead']),
      onTimeCycles: _i(d['onTimeCycles']),
      totalCycles: _i(d['totalCycles']),
      khatmasGroup: _i(d['khatmasGroup']),
      khatmasPersonal: _i(d['khatmasPersonal']),
      badges: {for (final b in (d['badges'] as List?) ?? const []) '$b'},
    );
  }
}

class UserService {
  UserService._();
  static final UserService instance = UserService._();

  DocumentReference<Map<String, dynamic>>? get _me {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Stream<UserStats> stats() {
    final ref = _me;
    if (ref == null) return Stream.value(UserStats.fromMap(null));
    return ref.snapshots().map((s) => UserStats.fromMap(s.data()));
  }

  Future<void> setLocale(String locale) async {
    final ref = _me;
    if (ref == null) return;
    try {
      await ref.update({'locale': locale});
    } catch (_) {
      // ملف المستخدم ممكن ميكونش اتعمل لسه، ومش مشكلة.
    }
  }

  /// بيحذف الحساب وكل بياناته من السيرفر.
  Future<void> deleteAccount() async {
    await FirebaseFunctions.instanceFor(region: 'me-central1').httpsCallable('deleteAccount').call<Object?>();
  }

  Future<void> addFcmToken(String token) async {
    final ref = _me;
    if (ref == null) return;
    final snap = await ref.get();
    final tokens = List<String>.from((snap.data()?['fcmTokens'] as List?) ?? const []);
    if (tokens.contains(token)) return;
    tokens.add(token);
    // آخر ١٠ أجهزة بس (القاعدة في قواعد الأمان).
    await ref.update({'fcmTokens': tokens.length > 10 ? tokens.sublist(tokens.length - 10) : tokens});
  }
}
