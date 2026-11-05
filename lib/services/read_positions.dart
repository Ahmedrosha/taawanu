import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'prefs.dart';

/// آخر آية وقف عندها في كل ختمة: على الموبايل، ونسخة على السيرفر (خاصة بصاحبها بس)
/// عشان يفتح من نفس الآية حتى لو غيّر الموبايل. المفتاح فيه حدود الورد، فكل دورة ليها مكانها.
class ReadPositions {
  ReadPositions._();

  static final ReadPositions instance = ReadPositions._();

  Timer? _timer;
  (String, String, String)? _pending; // (المستند، المفتاح، المكان)

  DocumentReference<Map<String, dynamic>>? _doc(String docId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('readPositions').doc(docId);
  }

  String? local(String key) => Prefs.instance.readPosition(key);

  /// بيحفظ على الموبايل على طول، وعلى السيرفر بعد ثواني (أو فورًا مع [flush]).
  void save({required String docId, required String key, required String pos}) {
    Prefs.instance.setReadPosition(key, pos);
    Prefs.instance.setReadPositionAt(key, DateTime.now().millisecondsSinceEpoch);
    _pending = (docId, key, pos);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    final p = _pending;
    _pending = null;
    if (p == null) return;
    final (docId, key, pos) = p;
    try {
      await _doc(docId)?.set({'key': key, 'pos': pos, 'at': FieldValue.serverTimestamp()});
    } catch (_) {
      // من غير نت: النسخة اللي على الموبايل كفاية، والسيرفر بيتحدّث المرة الجاية.
    }
  }

  /// المكان اللي على السيرفر لو أحدث من اللي على الموبايل (ولنفس الورد).
  Future<String?> remoteIfNewer({required String docId, required String key}) async {
    try {
      final d = await _doc(docId)?.get();
      final data = d?.data();
      if (data == null || data['key'] != key) return null;
      final pos = data['pos'] as String?;
      final at = (data['at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final localAt = Prefs.instance.readPositionAt(key) ?? 0;
      if (pos == null || pos == local(key) || at <= localAt) return null;
      return pos;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear({required String docId, required String key}) async {
    _pending = null;
    _timer?.cancel();
    await Prefs.instance.clearReadPosition(key);
    try {
      await _doc(docId)?.delete();
    } catch (_) {}
  }
}
