import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

class GroupsService {
  GroupsService._();
  static final GroupsService instance = GroupsService._();

  /// نفس منطقة الـFunctions على السيرفر (الدوحة).
  final _functions = FirebaseFunctions.instanceFor(region: 'me-central1');
  final _db = FirebaseFirestore.instance;

  /// مجموعات المستخدم الحالي، الأحدث الأول.
  Stream<List<MyGroup>> myGroups() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(uid)
        .collection('groups')
        .orderBy('joinedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MyGroup.fromDoc).toList());
  }

  /// بيرجّع معرّف المجموعة الجديدة.
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
  }) async {
    final result = await _functions.httpsCallable('createGroup').call<Object?>({
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
    // الرد بيوصل كـ Map عامة من المنصة، فبنحوّله بأمان.
    final data = Map<String, dynamic>.from(result.data! as Map);
    return data['groupId'] as String;
  }
}
