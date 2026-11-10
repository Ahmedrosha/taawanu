import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// إشعار محفوظ في الجرس (السيرفر بيكتبه باللغتين).
class InboxItem {
  const InboxItem({
    required this.id,
    required this.titleAr,
    required this.bodyAr,
    required this.titleEn,
    required this.bodyEn,
    required this.groupId,
    required this.type,
    required this.createdAt,
    this.fromUid,
    this.fromName,
  });

  /// الرسائل: مين بعتها (عشان الرد).
  final String? fromUid, fromName;

  final String id;
  final String titleAr, bodyAr, titleEn, bodyEn;
  final String? groupId;
  final String? type;
  final DateTime? createdAt;

  String title(String lang) => lang == 'en' && titleEn.isNotEmpty ? titleEn : titleAr;
  String body(String lang) => lang == 'en' && bodyEn.isNotEmpty ? bodyEn : bodyAr;

  factory InboxItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    Map<String, dynamic> m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
    final ar = m(d['ar']), en = m(d['en']);
    return InboxItem(
      id: doc.id,
      titleAr: (ar['title'] as String?) ?? '',
      bodyAr: (ar['body'] as String?) ?? '',
      titleEn: (en['title'] as String?) ?? '',
      bodyEn: (en['body'] as String?) ?? '',
      groupId: d['groupId'] as String?,
      type: d['type'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      fromUid: d['fromUid'] as String?,
      fromName: d['fromName'] as String?,
    );
  }
}

/// الجرس: آخر الإشعارات، وآخر مرة المستخدم فتح الصفحة (عشان نعرف الجديد).
class InboxService {
  InboxService._();
  static final InboxService instance = InboxService._();

  static const limit = 100;

  /// من التاريخ ده الرسائل بقت في قسم الرسائل، فمبتظهرش في الجرس (اللي قبله بيفضل زي ما هو).
  static final _messagesMoved = DateTime.utc(2026, 11, 10, 17);

  static bool _inBell(Map<String, dynamic> d) {
    final type = d['type'];
    if (type != 'message' && type != 'reminder') return true;
    final at = (d['createdAt'] as Timestamp?)?.toDate();
    return at != null && at.isBefore(_messagesMoved);
  }

  DocumentReference<Map<String, dynamic>>? get _me {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Stream<List<InboxItem>> items() {
    final me = _me;
    if (me == null) return Stream.value(const []);
    return me
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => [for (final d in s.docs) if (_inBell(d.data())) InboxItem.fromDoc(d)]);
  }

  /// آخر مرة فتح صفحة الإشعارات (null لو عمره ما فتحها).
  Stream<DateTime?> seenAt() {
    final me = _me;
    if (me == null) return Stream.value(null);
    return me.snapshots().map((s) => (s.data()?['notifSeenAt'] as Timestamp?)?.toDate());
  }

  /// عدد الإشعارات الجديدة من آخر فتح.
  /// ملف المستخدم بيتحدّث كتير (النقاط مثلًا)، فبنغيّر الاستعلام بس لما وقت آخر فتح يتغير.
  Stream<int> unreadCount() {
    final me = _me;
    if (me == null) return Stream.value(0);
    late final StreamController<int> out;
    StreamSubscription<DateTime?>? outer;
    StreamSubscription<int>? inner;
    var started = false;
    DateTime? current;
    out = StreamController<int>(
      onListen: () {
        outer = seenAt().listen((seen) {
          if (started && seen == current) return;
          started = true;
          current = seen;
          final old = inner;
          if (old != null) unawaited(old.cancel());
          Query<Map<String, dynamic>> q = me.collection('notifications');
          if (seen != null) q = q.where('createdAt', isGreaterThan: Timestamp.fromDate(seen));
          inner = q.limit(limit).snapshots().map((s) => s.docs.where((d) => _inBell(d.data())).length).listen(out.add, onError: (_) {});
        }, onError: (_) {});
      },
      onCancel: () async {
        await inner?.cancel();
        await outer?.cancel();
      },
    );
    return out.stream;
  }

  Future<void> markSeen() async {
    try {
      await _me?.update({'notifSeenAt': FieldValue.serverTimestamp()});
    } catch (_) {
      // مش أساسي.
    }
  }
}
