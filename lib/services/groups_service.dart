import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/group_models.dart';
import '../models/group_options.dart';

/// مجموعة في قايمة "مجموعاتي".
class MyGroup {
  const MyGroup({
    required this.id,
    required this.name,
    required this.type,
    required this.role,
    required this.wardQuarters,
  });

  final String id;
  final String name;
  final String type;
  final String role;
  final int wardQuarters;

  bool get isPrivate => type == 'private';

  factory MyGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MyGroup(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      type: (d['type'] as String?) ?? 'private',
      role: (d['role'] as String?) ?? 'member',
      wardQuarters: (d['wardQuarters'] as num?)?.toInt() ?? 8,
    );
  }
}

/// كل التعامل مع المجموعات: القراءة من Firestore، والتعديل عن طريق السيرفر.
class GroupsService {
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
    return _group(groupId)
        .collection('cycles')
        .doc('$cycle')
        .collection('assignments')
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? Assignment.fromDoc(d) : null);
  }

  /// الأوراد الإضافية اللي لسه مخلصتش (متاحة أو متحددة لحد).
  Stream<List<Portion>> activePortions(String groupId) => _group(groupId)
      .collection('portions')
      .where('status', whereIn: ['open', 'assigned'])
      .snapshots()
      .map((s) => s.docs.map(Portion.fromDoc).toList()..sort((a, b) => a.fromQuarter.compareTo(b.fromQuarter)));

  /// الأوراد الإضافية اللي خلصت في الدورة دي (بتفضل ظاهرة لحد آخرها).
  Stream<List<Portion>> donePortions(String groupId, int cycle) => _group(groupId)
      .collection('portions')
      .where('status', isEqualTo: 'done')
      .where('doneCycle', isEqualTo: cycle)
      .snapshots()
      .map((s) => s.docs.map(Portion.fromDoc).toList());

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

  /// الأدمن أو المساعد بيسجّل ورد عضو (من غير نقاط).
  Future<void> recordProgress(String groupId, String memberUid, int quartersRead) =>
      _call('recordProgress', {'groupId': groupId, 'uid': memberUid, 'quartersRead': quartersRead});

  Future<void> recordPortion(String groupId, String portionId, int quartersRead) =>
      _call('recordProgress', {'groupId': groupId, 'portionId': portionId, 'quartersRead': quartersRead});

  /// تقدم ورد إضافي ربع ربع. بيرجّع النقاط (بالسالب لو تراجع عن ورد كان خلص).
  Future<int> updatePortionProgress(String groupId, String portionId, int quartersRead) async {
    final data = await _call('updatePortionProgress', {'groupId': groupId, 'portionId': portionId, 'quartersRead': quartersRead});
    return (data['points'] as num?)?.toInt() ?? 0;
  }

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

  /// بيرجّع النقاط اللي اتكسبت (لو الورد خلص).
  Future<int> updateProgress(String groupId, int quartersRead) async {
    final data = await _call('updateProgress', {'groupId': groupId, 'quartersRead': quartersRead});
    return (data['points'] as num?)?.toInt() ?? 0;
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
