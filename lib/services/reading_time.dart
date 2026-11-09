import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// وقت التلاوة: الوقت اللي المصحف فيه قدامك وإنت بتقرا أو بتسمع (بيقف بعد دقيقتين من غير أي حركة).
/// بيتحفظ لكل يوم على الموبايل وفي حسابك (users/{uid}/private/readingTime) عشان ميضيعش لو غيرت الموبايل.
class ReadingTime extends ChangeNotifier {
  ReadingTime._();
  static final instance = ReadingTime._();

  static const idleLimit = Duration(minutes: 2);
  static const _tick = Duration(seconds: 5);

  Timer? _timer;
  DateTime _lastActivity = DateTime(2000);
  bool Function()? _busy;
  final _pending = <String, int>{};
  Map<String, int> _server = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _subUid;
  int _sinceFlush = 0;

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('private').doc('readingTime');
  }

  /// شاشة المصحف اتفتحت. [busy] = التلاوة أو القراءة التلقائية شغالة (بتتحسب حتى من غير لمس).
  void begin(bool Function() busy) {
    _busy = busy;
    activity();
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  /// لمس أو تقليب أو تمرير.
  void activity() => _lastActivity = DateTime.now();

  /// التطبيق راح للخلفية أو المصحف اتقفل.
  void end() {
    _timer?.cancel();
    _timer = null;
    _busy = null;
    flush();
  }

  void pauseCounting() {
    _timer?.cancel();
    _timer = null;
    flush();
  }

  void resumeCounting() {
    if (_busy == null || _timer != null) return;
    activity();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  void _onTick() {
    final now = DateTime.now();
    final active = (_busy?.call() ?? false) || now.difference(_lastActivity) < idleLimit;
    if (!active) return;
    final k = dayKey(now);
    _pending[k] = (_pending[k] ?? 0) + _tick.inSeconds;
    Prefs.instance.addReadingSeconds(k, _tick.inSeconds);
    _sinceFlush += _tick.inSeconds;
    if (_sinceFlush >= 60) flush();
    notifyListeners();
  }

  /// بيبعت الثواني اللي اتجمعت للسيرفر.
  Future<void> flush() async {
    _sinceFlush = 0;
    final doc = _doc;
    if (doc == null || _pending.isEmpty) return;
    final send = Map<String, int>.from(_pending);
    _pending.clear();
    try {
      await doc.set({
        'days': {for (final e in send.entries) e.key: FieldValue.increment(e.value)},
        'at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // من غير نت: نرجّعها وتتبعت بعدين.
      send.forEach((k, v) => _pending[k] = (_pending[k] ?? 0) + v);
    }
  }

  /// ثواني كل يوم: من الحساب، ولو الحساب مش متاح من الموبايل.
  Map<String, int> get days {
    final local = Prefs.instance.readingSeconds;
    final out = <String, int>{..._server};
    local.forEach((k, v) {
      final pending = _pending[k] ?? 0;
      final fromServer = (out[k] ?? 0) + pending;
      out[k] = fromServer > v ? fromServer : v;
    });
    return out;
  }

  /// بيسمع لحسابه عشان الأرقام تبقى من كل الأجهزة.
  void watch() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == _subUid) return;
    _sub?.cancel();
    _server = {};
    _subUid = uid;
    final doc = _doc;
    if (doc == null) return;
    _sub = doc.snapshots().listen((s) {
      final d = (s.data()?['days'] as Map<String, dynamic>?) ?? const {};
      _server = {for (final e in d.entries) e.key: (e.value as num).toInt()};
      notifyListeners();
    }, onError: (_) {});
  }

  int secondsOn(DateTime d) => days[dayKey(d)] ?? 0;

  /// آخر ٧ أيام (أقدم يوم الأول).
  List<(DateTime, int)> lastWeek() {
    final today = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          return (d, secondsOn(d));
        }(),
    ];
  }
}
