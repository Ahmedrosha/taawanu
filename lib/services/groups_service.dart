import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../models/group_models.dart';
import '../models/group_options.dart';
import 'prefs.dart';

/// مجموعة في قايمة "مجموعاتي".
class MyGroup {
  const MyGroup({
    required this.id,
    required this.name,
    required this.type,
    required this.role,
    required this.wardQuarters,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String type;
  final String role;
  final int wardQuarters;
  final DateTime? joinedAt;

  bool get isPrivate => type == 'private';
  bool get isManager => role == 'admin' || role == 'assistant';

  factory MyGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MyGroup(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      type: (d['type'] as String?) ?? 'private',
      role: (d['role'] as String?) ?? 'member',
      wardQuarters: (d['wardQuarters'] as num?)?.toInt() ?? 8,
      joinedAt: (d['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// نتيجة مزامنة قراءة اتسجلت من غير نت.
enum SyncNotice { synced, late, taken, failed }

/// كل التعامل مع المجموعات: القراءة من Firestore، والتعديل عن طريق السيرفر.
class GroupsService with WidgetsBindingObserver {
  GroupsService._();
  static final GroupsService instance = GroupsService._();

  /// نفس منطقة الـFunctions على السيرفر (الدوحة).
  final _functions = FirebaseFunctions.instanceFor(region: 'me-central1');
  final _db = FirebaseFirestore.instance;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _group(String id) => _db.collection('groups').doc(id);

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final result = await _functions.httpsCallable(name).call<Object?>(data);
    final raw = result.data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  // ---------- قراءة ----------

  Stream<List<MyGroup>> myGroups() {
    final id = uid;
    if (id == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(id)
        .collection('groups')
        .orderBy('joinedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MyGroup.fromDoc).toList());
  }

  Stream<Group?> group(String id) =>
      _group(id).snapshots().map((d) => d.exists ? Group.fromDoc(d) : null);

  Stream<List<Member>> members(String groupId) => _group(groupId)
      .collection('members')
      .snapshots()
      .map((s) => s.docs.map(Member.fromDoc).toList()..sort((a, b) => b.points.compareTo(a.points)));

  Stream<Cycle?> cycle(String groupId, int number) => _group(groupId)
      .collection('cycles')
      .doc('$number')
      .snapshots()
      .map((d) => d.exists ? Cycle.fromDoc(d) : null);

  /// ورد عضو معين في دورة (للأدمن والمساعد).
  Future<Assignment?> memberAssignment(String groupId, int cycle, String memberUid) async {
    final d = await _group(groupId).collection('cycles').doc('$cycle').collection('assignments').doc(memberUid).get();
    return d.exists ? Assignment.fromDoc(d) : null;
  }

  Stream<Assignment?> myAssignment(String groupId, int cycle) {
    final id = uid;
    if (id == null || cycle < 1) return Stream.value(null);
    final src = _group(groupId)
        .collection('cycles')
        .doc('$cycle')
        .collection('assignments')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? Assignment.fromDoc(d) : null);
    // اللي اتسجل من غير نت بيبان على طول، لحد ما يتبعت.
    return _overlay(src, (a) {
      final q = pendingRead(groupId, cycle: cycle);
      return a == null || q == null ? a : a.withRead(q);
    });
  }

  /// الأوراد الإضافية اللي لسه مخلصتش (متاحة أو متحددة لحد).
  Stream<List<Portion>> activePortions(String groupId) => _overlay(
        _group(groupId)
            .collection('portions')
            .where('status', whereIn: ['open', 'assigned'])
            .snapshots()
            .map((s) => s.docs.map(Portion.fromDoc).toList()..sort((a, b) => a.fromQuarter.compareTo(b.fromQuarter))),
        (list) => [
          for (final p in list)
            if (p.assignee != null && p.assignee == uid && pendingRead(groupId, portionId: p.id) != null)
              p.withRead(pendingRead(groupId, portionId: p.id)!)
            else
              p,
        ],
      );

  /// الأوراد الإضافية اللي خلصت في الدورة دي (بتفضل ظاهرة لحد آخرها).
  Stream<List<Portion>> donePortions(String groupId, int cycle) => _group(groupId)
      .collection('portions')
      .where('status', isEqualTo: 'done')
      .where('doneCycle', isEqualTo: cycle)
      .snapshots()
      .map((s) => s.docs.map(Portion.fromDoc).toList());

  /// الأوراد الإضافية اللي اتعملت من دورة معينة (لتقرير دورة فاتت).
  Future<List<Portion>> cyclePortions(String groupId, int cycle) async {
    final s = await _group(groupId).collection('portions').where('cycle', isEqualTo: cycle).get();
    return s.docs.map(Portion.fromDoc).toList();
  }

  /// كل الدورات (للتقرير الشامل).
  Future<List<Cycle>> allCycles(String groupId) async {
    final s = await _group(groupId).collection('cycles').get();
    return s.docs.map(Cycle.fromDoc).toList()..sort((a, b) => a.number.compareTo(b.number));
  }

  /// كل الأوراد الإضافية (للتقرير الشامل).
  Future<List<Portion>> allPortions(String groupId) async {
    final s = await _group(groupId).collection('portions').get();
    return s.docs.map(Portion.fromDoc).toList();
  }

  /// الختمات اللي خلصت: رقم الدورة ← وقت ما خلصت.
  Future<Map<int, DateTime>> completedKhatmas(String groupId) async {
    final s = await _group(groupId).collection('khatmas').get();
    return {
      for (final d in s.docs)
        if (d.data()['completedAt'] is Timestamp)
          ((d.data()['cycle'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0): (d.data()['completedAt'] as Timestamp).toDate(),
    };
  }

  /// المجموعات العامة اللي فيها خانات فاضية.
  Future<List<Group>> explorePublic() async {
    final s = await _db
        .collection('groups')
        .where('type', isEqualTo: 'public')
        .where('isOpen', isEqualTo: true)
        .where('hasFreeSlots', isEqualTo: true)
        .orderBy('memberCount', descending: true)
        .limit(50)
        .get();
    return s.docs.map(Group.fromDoc).toList();
  }

  // ---------- إنشاء وإدارة ----------

  Future<String> createGroup({
    required String name,
    required bool isPrivate,
    required int wardQuarters,
    required int cycleCount,
    required CycleUnit cycleUnit,
    required int cycleStartDay,
    required int cycleStartHour,
    required int cycleStartDayOfMonth,
    required LatePolicy lateDefault,
    int startSegment = 0,
  }) async {
    final data = await _call('createGroup', {
      'startSegment': startSegment,
      'name': name,
      'type': isPrivate ? 'private' : 'public',
      'wardQuarters': wardQuarters,
      'cycleCount': cycleCount,
      'cycleUnit': cycleUnit.name,
      'cycleStartDay': cycleStartDay,
      'cycleStartHour': cycleStartHour,
      'cycleStartDayOfMonth': cycleStartDayOfMonth,
      'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'lateDefault': lateDefault.name,
    });
    return data['groupId'] as String;
  }

  Future<void> updateSettings(String groupId, Map<String, dynamic> fields) =>
      _call('updateGroupSettings', {'groupId': groupId, ...fields});

  Future<void> startKhatma(String groupId) => _call('startKhatma', {'groupId': groupId});

  Future<void> leave(String groupId) => _call('leaveGroup', {'groupId': groupId});

  Future<void> removeMember(String groupId, String memberUid) =>
      _call('removeMember', {'groupId': groupId, 'uid': memberUid});

  Future<void> setRole(String groupId, String memberUid, String role) =>
      _call('setRole', {'groupId': groupId, 'uid': memberUid, 'role': role});

  /// الأدمن أو المساعد بيكتب اسم لعضو في المجموعة دي.
  Future<void> setMemberName(String groupId, String memberUid, String name) =>
      _call('setMemberName', {'groupId': groupId, 'uid': memberUid, 'name': name});

  /// الأدمن أو المساعد بيسجّل ورد عضو (من غير نقاط).
  Future<void> recordProgress(String groupId, String memberUid, int quartersRead) =>
      _call('recordProgress', {'groupId': groupId, 'uid': memberUid, 'quartersRead': quartersRead});

  Future<void> recordPortion(String groupId, String portionId, int quartersRead) =>
      _call('recordProgress', {'groupId': groupId, 'portionId': portionId, 'quartersRead': quartersRead});

  /// تقدم ورد إضافي ربع ربع. بيرجّع النقاط (بالسالب لو تراجع عن ورد كان خلص).
  Future<int> updatePortionProgress(String groupId, String portionId, int quartersRead) =>
      _progress(groupId, portionId, quartersRead);

  /// تغيير جزء عضو، وبيتطبّق على طول. لو الجزء مع حد، أو حد فيهم كان قرا،
  /// السيرفر بيرجّع تفاصيل عشان نسأل الأدمن، وبعدها بنبعت [confirm].
  Future<MoveOutcome> moveMember(String groupId, String memberUid, int segment, {bool confirm = false}) async {
    final d = await _call('moveMember', {'groupId': groupId, 'uid': memberUid, 'segment': segment, 'confirm': confirm});
    return MoveOutcome.fromMap(d);
  }

  Future<void> transferAdmin(String groupId, String memberUid) =>
      _call('transferAdmin', {'groupId': groupId, 'uid': memberUid});

  Future<void> deleteGroup(String groupId) => _call('deleteGroup', {'groupId': groupId});

  // ---------- الدعوات والانضمام ----------

  /// بيرجّع رابط الدعوة.
  Future<String> createInvite(String groupId, {required int days, int? maxUses}) async {
    final data = await _call('createInvite', {'groupId': groupId, 'days': days, 'maxUses': maxUses});
    return data['url'] as String;
  }

  Future<GroupPreview> previewInvite(String codeOrLink) async =>
      GroupPreview.fromMap(await _call('previewInvite', {'code': codeOrLink}));

  Future<GroupPreview> previewPublic(String groupId) async =>
      GroupPreview.fromMap(await _call('previewPublicGroup', {'groupId': groupId}));

  Future<String> join(String codeOrLink, {int? segment}) async =>
      (await _call('joinGroup', {'code': codeOrLink, 'segment': segment}))['groupId'] as String;

  Future<String> joinPublic(String groupId, {int? segment}) async =>
      (await _call('joinPublicGroup', {'groupId': groupId, 'segment': segment}))['groupId'] as String;

  // ---------- القراءة والتقدم ----------

  /// بيرجّع النقاط اللي اتكسبت (لو الورد خلص)، أو [savedOffline] لو اتسجل على الموبايل من غير نت.
  Future<int> updateProgress(String groupId, int quartersRead) => _progress(groupId, null, quartersRead);

  // ---------- القراءة من غير نت ----------

  /// القراءة اتسجلت على الموبايل وهتتبعت لما النت يرجع.
  static const savedOffline = -1 << 30;

  /// بيتغير مع كل تسجيل أو إرسال، عشان الشاشات تعرض القراءة اللي مستنية.
  final pendingChanges = ValueNotifier<int>(0);

  /// بيتنادي بعد ما قراءة من غير نت توصل للسيرفر (للرسالة اللي بتظهر للمستخدم).
  void Function(SyncNotice notice, int points)? onSyncNotice;

  Timer? _syncTimer;
  bool _flushing = false;

  Map<String, Map<String, dynamic>> _pending() {
    try {
      final m = jsonDecode(Prefs.instance.pendingProgress) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: Map<String, dynamic>.from(e.value as Map)};
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePending(Map<String, Map<String, dynamic>> m) async {
    await Prefs.instance.setPendingProgress(jsonEncode(m));
    pendingChanges.value++;
  }

  String _key(String groupId, {int? cycle, String? portionId}) => '$uid|$groupId|${portionId == null ? 'a$cycle' : 'p$portionId'}';

  /// القراءة اللي مستنية لورد معين (لو فيه).
  int? pendingRead(String groupId, {int? cycle, String? portionId}) =>
      (_pending()[_key(groupId, cycle: cycle, portionId: portionId)]?['q'] as num?)?.toInt();

  bool get hasPending => _pending().keys.any((k) => k.startsWith('$uid|'));

  /// بيبدأ يبعت القراءات اللي مستنية: كل دقيقة، ولما التطبيق يرجع قدام المستخدم.
  void startSync() {
    WidgetsBinding.instance.addObserver(this);
    _syncTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (hasPending) flushPending();
    });
    flushPending();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) flushPending();
  }

  Future<bool> _online() async {
    try {
      final r = await InternetAddress.lookup('firestore.googleapis.com').timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _isNetwork(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    if (e is FirebaseFunctionsException) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') return true;
      final m = '${e.message}'.toLowerCase();
      return e.code == 'internal' && (m.contains('network') || m.contains('offline') || m.contains('connection'));
    }
    return false;
  }

  /// الدورة الحالية من النسخة اللي على الموبايل (من غير نت).
  Future<int?> _cachedCycle(String groupId) async {
    try {
      final g = await _group(groupId).get(const GetOptions(source: Source.cache));
      return (g.data()?['currentCycle'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<int> _progress(String groupId, String? portionId, int q) async {
    final cycle = portionId == null ? await _cachedCycle(groupId) : null;
    final key = _key(groupId, cycle: cycle, portionId: portionId);
    Future<int> queue() async {
      final m = _pending();
      m[key] = {
        'g': groupId,
        if (portionId != null) 'p': portionId,
        if (cycle != null) 'c': cycle,
        'q': q,
        // وقت القراءة: السيرفر بيحسب الميعاد عليه (لو في آخر ٤٨ ساعة).
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      await _savePending(m);
      return savedOffline;
    }

    if (!await _online()) return queue();
    try {
      final data = portionId == null
          ? await _call('updateProgress', {'groupId': groupId, 'quartersRead': q})
          : await _call('updatePortionProgress', {'groupId': groupId, 'portionId': portionId, 'quartersRead': q});
      final m = _pending();
      if (m.remove(key) != null) await _savePending(m);
      return (data['points'] as num?)?.toInt() ?? 0;
    } catch (e) {
      if (_isNetwork(e)) return queue();
      rethrow;
    }
  }

  /// بيبعت القراءات اللي اتسجلت من غير نت، بالترتيب.
  Future<void> flushPending() async {
    if (_flushing || uid == null || !hasPending) return;
    _flushing = true;
    try {
      if (!await _online()) return;
      final mine = _pending().entries.where((e) => e.key.startsWith('$uid|')).toList()
        ..sort((a, b) => ((a.value['at'] as num?) ?? 0).compareTo((b.value['at'] as num?) ?? 0));
      for (final e in mine) {
        final d = e.value;
        try {
          final res = d['p'] == null
              ? await _call('updateProgress', {
                  'groupId': d['g'], 'quartersRead': d['q'], 'readAt': d['at'], 'cycle': d['c'],
                })
              : await _call('updatePortionProgress', {
                  'groupId': d['g'], 'portionId': d['p'], 'quartersRead': d['q'], 'readAt': d['at'],
                });
          final m = _pending()..remove(e.key);
          await _savePending(m);
          final points = (res['points'] as num?)?.toInt() ?? 0;
          final synced = res['synced'] as String?;
          onSyncNotice?.call(
            synced == 'taken' ? SyncNotice.taken : (synced == 'carry' ? SyncNotice.late : SyncNotice.synced),
            points,
          );
        } catch (err) {
          if (_isNetwork(err)) break;
          // السيرفر رفضها (الورد اتغير أو اتقفل): مش هنفضل نبعتها.
          final m = _pending()..remove(e.key);
          await _savePending(m);
          onSyncNotice?.call(SyncNotice.failed, 0);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// بيضيف القراءة اللي مستنية على بيانات السيرفر، وبيعيد العرض لما حاجة تتسجل أو تتبعت.
  Stream<T> _overlay<T>(Stream<T> src, T Function(T) apply) {
    late StreamController<T> c;
    StreamSubscription<T>? sub;
    T? last;
    var has = false;
    void emit() {
      if (has && !c.isClosed) c.add(apply(last as T));
    }

    c = StreamController<T>(
      onListen: () {
        sub = src.listen((v) {
          last = v;
          has = true;
          emit();
        }, onError: c.addError, onDone: c.close);
        pendingChanges.addListener(emit);
      },
      onCancel: () async {
        pendingChanges.removeListener(emit);
        await sub?.cancel();
      },
    );
    return c.stream;
  }

  /// رسالة جوه المجموعة: [to] = uid أو قايمة uids، أو 'late' لتذكير المتأخرين. بيرجع عدد اللي وصلهم.
  Future<int> sendMessage(String groupId, Object to, String text) async {
    final data = await _call('sendGroupMessage', {'groupId': groupId, 'to': to, 'text': text});
    return (data['sent'] as num?)?.toInt() ?? 0;
  }

  /// قفل الأوراد اللي لسه متقرتش من دورة فاتت.
  Future<int> closeCyclePortions(String groupId, int cycle) async {
    final data = await _call('closeCyclePortions', {'groupId': groupId, 'cycle': cycle});
    return (data['closed'] as num?)?.toInt() ?? 0;
  }

  Future<void> claimPortion(String groupId, String portionId) =>
      _call('claimPortion', {'groupId': groupId, 'portionId': portionId});

  Future<void> assignPortion(String groupId, String portionId, String? memberUid) =>
      _call('assignPortion', {'groupId': groupId, 'portionId': portionId, 'uid': memberUid});

  Future<int> completePortion(String groupId, String portionId) async {
    final data = await _call('completePortion', {'groupId': groupId, 'portionId': portionId});
    return (data['points'] as num?)?.toInt() ?? 0;
  }
}

/// نتيجة تغيير الجزء: اتطبّق، أو محتاج تأكيد.
class MoveOutcome {
  const MoveOutcome({required this.needsConfirm, this.otherName, this.otherRead = 0, this.volunteerName, this.volunteerRead = 0, this.myRead = 0, this.quarterCount = 0});

  factory MoveOutcome.fromMap(Map<String, dynamic> d) {
    final other = d['other'] as Map?;
    final vol = d['volunteer'] as Map?;
    return MoveOutcome(
      needsConfirm: d['applied'] == 'confirm',
      otherName: other?['name'] as String?,
      otherRead: (other?['read'] as num?)?.toInt() ?? 0,
      volunteerName: vol?['name'] as String?,
      volunteerRead: (vol?['read'] as num?)?.toInt() ?? 0,
      myRead: (d['myRead'] as num?)?.toInt() ?? 0,
      quarterCount: (d['quarterCount'] as num?)?.toInt() ?? 0,
    );
  }

  final bool needsConfirm;
  final String? otherName;
  final int otherRead;
  final String? volunteerName;
  final int volunteerRead;
  final int myRead;
  final int quarterCount;
}
