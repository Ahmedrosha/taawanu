import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// رسالة في قسم الرسائل (نسختي منها: اللي بعتّها أو اللي استلمتها).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.thread,
    required this.groupId,
    required this.groupName,
    required this.peerUid,
    required this.peerName,
    required this.text,
    required this.mine,
    required this.read,
    required this.fromName,
    required this.type,
    required this.at,
  });

  final String id, thread, groupId, groupName, peerUid, peerName, text, fromName, type;
  final bool mine, read;
  final DateTime? at;

  /// محادثة العضو مع إدارة المجموعة (مش مع شخص واحد).
  bool get withManagers => peerUid == 'managers';

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    String s(String k) => (d[k] as String?) ?? '';
    return ChatMessage(
      id: doc.id,
      thread: s('thread'),
      groupId: s('groupId'),
      groupName: s('groupName'),
      peerUid: s('peerUid'),
      peerName: s('peerName'),
      text: s('text'),
      fromName: s('fromName'),
      type: s('type'),
      mine: d['mine'] == true,
      read: d['read'] == true,
      // لسه مكتوبة حالًا ووقت السيرفر موصلش: دلوقتي.
      at: (d['at'] as Timestamp?)?.toDate(),
    );
  }
}

/// محادثة: آخر رسالة فيها وعدد اللي لسه متقراش.
class Conversation {
  const Conversation(this.last, this.unread);
  final ChatMessage last;
  final int unread;
}

class MessagesService {
  MessagesService._();
  static final MessagesService instance = MessagesService._();

  static const limit = 400;

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).collection('messages');
  }

  /// آخر الرسائل (الأحدث الأول).
  Stream<List<ChatMessage>> recent() {
    final c = _col;
    if (c == null) return Stream.value(const []);
    return c.orderBy('at', descending: true).limit(limit).snapshots(includeMetadataChanges: false).map(
          (s) => [for (final d in s.docs) ChatMessage.fromDoc(d)],
        );
  }

  /// المحادثات من آخر الرسائل (الأحدث الأول).
  static List<Conversation> conversations(List<ChatMessage> messages) {
    final last = <String, ChatMessage>{};
    final unread = <String, int>{};
    for (final m in messages) {
      last.putIfAbsent(m.thread, () => m);
      if (!m.mine && !m.read) unread[m.thread] = (unread[m.thread] ?? 0) + 1;
    }
    return [for (final e in last.entries) Conversation(e.value, unread[e.key] ?? 0)];
  }

  /// عدد الرسائل اللي لسه متقراش.
  Stream<int> unreadCount() {
    final c = _col;
    if (c == null) return Stream.value(0);
    return c.where('read', isEqualTo: false).limit(100).snapshots().map((s) => s.size);
  }

  /// بيعلّم رسايل المحادثة مقروءة.
  Future<void> markRead(Iterable<ChatMessage> messages) async {
    final c = _col;
    if (c == null) return;
    final todo = messages.where((m) => !m.mine && !m.read).toList();
    if (todo.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final m in todo.take(400)) {
        batch.update(c.doc(m.id), {'read': true});
      }
      await batch.commit();
    } catch (_) {
      // مش أساسي.
    }
  }
}
