import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/features/groups/group_summary_report.dart';
import 'package:taawanu/models/group_models.dart';

Group _group(int current) => Group(
      id: 'g',
      name: 'G',
      type: 'khatma',
      wardQuarters: 8,
      slots: 30,
      cycleCount: 1,
      cycleUnit: 'week',
      cycleStartDay: 5,
      cycleStartHour: 0,
      cycleStartDayOfMonth: 1,
      lateDefault: 'ask',
      adminId: 'a',
      memberCount: 3,
      status: 'active',
      currentCycle: current,
      isOpen: true,
      khatmasCompleted: 1,
    );

Member _m(String uid, int points, {DateTime? joined}) =>
    Member(uid: uid, role: 'member', slot: 0, name: uid, points: points, joinedAt: joined);

Cycle _c(int n, DateTime start, Map<String, String> statuses, {bool complete = false, int remaining = 0}) {
  var seg = 0;
  return Cycle(
    number: n,
    startedAt: start,
    endsAt: start.add(const Duration(days: 7)),
    segments: [for (final e in statuses.entries) Segment(seg: seg++, uid: e.key, status: e.value)],
    remainingQuarters: remaining,
    khatmaComplete: complete,
  );
}

Portion _p(int cycle, String? assignee, String origin) => Portion(
      id: '$cycle$assignee$origin',
      cycle: cycle,
      fromQuarter: 1,
      toQuarter: 8,
      quarterCount: 8,
      assignee: assignee,
      status: 'done',
      origin: origin,
    );

void main() {
  final now = DateTime(2026, 11, 21);
  final members = [_m('a', 50), _m('b', 30), _m('c', 10, joined: DateTime(2026, 11, 10))];
  final cycles = [
    _c(1, DateTime(2026, 6, 1), {'a': 'done', 'b': 'done', 'c': 'late'}, complete: true),
    _c(2, DateTime(2026, 11, 1), {'a': 'done', 'b': 'late', 'c': 'late_done'}),
    _c(3, DateTime(2026, 11, 8), {'a': 'done', 'b': 'done', 'c': 'done'}, complete: true),
    _c(4, DateTime(2026, 11, 15), {'a': 'pending', 'b': 'pending', 'c': 'pending'}, remaining: 200),
  ];
  final portions = [_p(2, 'a', 'volunteer'), _p(2, 'c', 'carry'), _p(1, 'b', 'distribute')];
  final khatmas = {1: DateTime(2026, 6, 6), 3: DateTime(2026, 11, 12)};

  GroupSummary run(DateTime? from) => GroupSummary.compute(
        group: _group(4),
        memberList: members,
        cycles: cycles,
        portions: portions,
        khatmaDates: khatmas,
        from: from,
        now: now,
      );

  test('all time', () {
    final s = run(null);
    expect(s.khatmas, 2);
    expect(s.cyclesEnded, 3); // الدورة الحالية مش محسوبة
    expect(s.assignedTurns, 9);
    expect(s.onTimeTurns, 6);
    expect(s.members['c']!.late, 2);
    expect(s.members['a']!.volunteered, 1);
    expect(s.members['c']!.volunteered, 0); // الترحيل لصاحبه مش تطوع
    expect(s.members['b']!.volunteered, 1);
    expect(s.bestKhatmaStreak, 1);
    expect(s.fastestKhatmaDays, 4);
    expect(s.firstStart, DateTime(2026, 6, 1));
    expect(s.topCommitted({'a': 50, 'b': 30, 'c': 10}).first.uid, 'a');
    expect(s.topLate().first.uid, 'c');
  });

  test('last 30 days', () {
    final s = run(now.subtract(const Duration(days: 30)));
    expect(s.khatmas, 1);
    expect(s.cyclesEnded, 2);
    expect(s.members['b']!.volunteered, 0);
    expect(s.newMembers, 1);
    expect(s.quartersRead, 240 * 2 + 40);
  });
}
