import 'package:cloud_firestore/cloud_firestore.dart';

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.type,
    required this.wardQuarters,
    required this.slots,
    required this.cycleCount,
    required this.cycleUnit,
    required this.cycleStartDay,
    required this.cycleStartHour,
    required this.cycleStartDayOfMonth,
    required this.lateDefault,
    required this.adminId,
    required this.memberCount,
    required this.status,
    required this.currentCycle,
    required this.isOpen,
    required this.khatmasCompleted,
    this.nextCycleAt,
  });

  final String id;
  final String name;
  final String type;
  final int wardQuarters;
  final int slots;
  final int cycleCount;
  final String cycleUnit;
  final int cycleStartDay;
  final int cycleStartHour;
  final int cycleStartDayOfMonth;
  final String lateDefault;
  final String adminId;
  final int memberCount;
  final String status;
  final int currentCycle;
  final bool isOpen;
  final int khatmasCompleted;
  final DateTime? nextCycleAt;

  bool get isPrivate => type == 'private';
  bool get isActive => status == 'active';
  bool get isFull => memberCount >= slots;

  factory Group.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Group(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      type: (d['type'] as String?) ?? 'private',
      wardQuarters: _int(d['wardQuarters'], 8),
      slots: _int(d['slots'], 30),
      cycleCount: _int(d['cycleCount'], 1),
      cycleUnit: (d['cycleUnit'] as String?) ?? 'week',
      cycleStartDay: _int(d['cycleStartDay'], 5),
      cycleStartHour: _int(d['cycleStartHour'], 6),
      cycleStartDayOfMonth: _int(d['cycleStartDayOfMonth'], 1),
      lateDefault: (d['lateDefault'] as String?) ?? 'ask',
      adminId: (d['adminId'] as String?) ?? '',
      memberCount: _int(d['memberCount'], 1),
      status: (d['status'] as String?) ?? 'forming',
      currentCycle: _int(d['currentCycle']),
      isOpen: (d['isOpen'] as bool?) ?? true,
      khatmasCompleted: _int(d['khatmasCompleted']),
      nextCycleAt: _date(d['nextCycleAt']),
    );
  }
}

class Member {
  const Member({
    required this.uid,
    required this.role,
    required this.slot,
    required this.name,
    this.photoUrl,
    required this.points,
  });

  final String uid;
  final String role;
  final int slot;
  final String name;
  final String? photoUrl;
  final int points;

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'admin' || role == 'assistant';

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Member(
      uid: doc.id,
      role: (d['role'] as String?) ?? 'member',
      slot: _int(d['slot']),
      name: (d['name'] as String?) ?? '—',
      photoUrl: d['photoUrl'] as String?,
      points: _int(d['points']),
    );
  }
}

class Segment {
  const Segment({required this.seg, required this.uid, required this.status});

  final int seg;
  final String? uid;
  final String status; // pending | in_progress | done | late | open
}

class Cycle {
  const Cycle({
    required this.number,
    required this.startedAt,
    required this.endsAt,
    required this.segments,
    required this.remainingQuarters,
    required this.khatmaComplete,
  });

  final int number;
  final DateTime? startedAt;
  final DateTime? endsAt;
  final List<Segment> segments;
  final int remainingQuarters;
  final bool khatmaComplete;

  int get doneSegments => segments.where((s) => s.status == 'done').length;

  factory Cycle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final raw = (d['segments'] as List?) ?? const [];
    return Cycle(
      number: _int(d['number']),
      startedAt: _date(d['startedAt']),
      endsAt: _date(d['endsAt']),
      segments: [
        for (final s in raw)
          if (s is Map)
            Segment(seg: _int(s['seg']), uid: s['uid'] as String?, status: (s['status'] as String?) ?? 'pending'),
      ],
      remainingQuarters: _int(d['remainingQuarters'], 240),
      khatmaComplete: (d['khatmaComplete'] as bool?) ?? false,
    );
  }
}

class Assignment {
  const Assignment({
    required this.fromQuarter,
    required this.toQuarter,
    required this.quarterCount,
    required this.quartersRead,
    required this.status,
    required this.closed,
  });

  final int fromQuarter;
  final int toQuarter;
  final int quarterCount;
  final int quartersRead;
  final String status;
  final bool closed;

  bool get isDone => status == 'done';
  double get progress => quarterCount == 0 ? 0 : quartersRead / quarterCount;

  factory Assignment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Assignment(
      fromQuarter: _int(d['fromQuarter'], 1),
      toQuarter: _int(d['toQuarter'], 1),
      quarterCount: _int(d['quarterCount'], 1),
      quartersRead: _int(d['quartersRead']),
      status: (d['status'] as String?) ?? 'pending',
      closed: (d['closed'] as bool?) ?? false,
    );
  }
}

class Portion {
  const Portion({
    required this.id,
    required this.cycle,
    required this.fromQuarter,
    required this.toQuarter,
    required this.quarterCount,
    required this.assignee,
    required this.status,
    required this.origin,
  });

  final String id;
  final int cycle;
  final int fromQuarter;
  final int toQuarter;
  final int quarterCount;
  final String? assignee;
  final String status; // open | assigned | done
  final String origin; // empty | carry | distribute | volunteer | ask | left

  bool get isOpen => status == 'open';

  factory Portion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Portion(
      id: doc.id,
      cycle: _int(d['cycle']),
      fromQuarter: _int(d['fromQuarter'], 1),
      toQuarter: _int(d['toQuarter'], 1),
      quarterCount: _int(d['quarterCount'], 1),
      assignee: d['assignee'] as String?,
      status: (d['status'] as String?) ?? 'open',
      origin: (d['origin'] as String?) ?? 'volunteer',
    );
  }
}

/// ملخص مجموعة قبل الانضمام (من السيرفر).
class GroupPreview {
  const GroupPreview({
    required this.groupId,
    required this.name,
    required this.type,
    required this.wardQuarters,
    required this.slots,
    required this.memberCount,
    required this.cycleCount,
    required this.cycleUnit,
    required this.cycleStartDay,
    required this.status,
    required this.adminName,
    required this.alreadyMember,
    required this.pickCycle,
    required this.takenSegments,
    this.code,
  });

  final String groupId;
  final String name;
  final String type;
  final int wardQuarters;
  final int slots;
  final int memberCount;
  final int cycleCount;
  final String cycleUnit;
  final int cycleStartDay;
  final String status;
  final String adminName;
  final bool alreadyMember;
  /// الدورة اللي الأجزاء المحجوزة محسوبة عليها.
  final int pickCycle;
  final Set<int> takenSegments;
  final String? code;

  /// أول جزء فاضي (الاختيار الافتراضي).
  int? get firstFreeSegment {
    for (var s = 0; s < slots; s++) {
      if (!takenSegments.contains(s)) return s;
    }
    return null;
  }

  factory GroupPreview.fromMap(Map<String, dynamic> d) => GroupPreview(
        groupId: d['groupId'] as String,
        name: (d['name'] as String?) ?? '',
        type: (d['type'] as String?) ?? 'private',
        wardQuarters: _int(d['wardQuarters'], 8),
        slots: _int(d['slots'], 30),
        memberCount: _int(d['memberCount'], 1),
        cycleCount: _int(d['cycleCount'], 1),
        cycleUnit: (d['cycleUnit'] as String?) ?? 'week',
        cycleStartDay: _int(d['cycleStartDay'], 5),
        status: (d['status'] as String?) ?? 'forming',
        adminName: (d['adminName'] as String?) ?? '',
        alreadyMember: (d['alreadyMember'] as bool?) ?? false,
        pickCycle: _int(d['pickCycle'], 1),
        takenSegments: {for (final s in (d['takenSegments'] as List?) ?? const []) _int(s)},
        code: d['code'] as String?,
      );
}
