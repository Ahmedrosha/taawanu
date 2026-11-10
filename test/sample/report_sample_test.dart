// مؤقت: بيطلع نسخة تجربة من تقرير الختمة (بيانات وهمية).
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:taawanu/features/groups/group_board_screen.dart';
import 'package:taawanu/features/groups/group_report.dart';
import 'package:taawanu/l10n/gen/app_localizations.dart';
import 'package:taawanu/models/group_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('report sample', () async {
    await initializeDateFormatting('ar');
    final t = lookupAppLocalizations(const Locale('ar'));
    const g = Group(
      id: 'g', name: 'ختمة العيلة', type: 'private', wardQuarters: 8, slots: 30, cycleCount: 1, cycleUnit: 'week',
      cycleStartDay: 5, cycleStartHour: 4, cycleStartDayOfMonth: 1, lateDefault: 'ask', adminId: 'u0', memberCount: 12,
      status: 'active', currentCycle: 3, isOpen: true, khatmasCompleted: 2,
    );
    final names = ['Ahmed Rashad', 'عمر', 'يوسف', 'مصطفى', 'أحمد', 'محمود', 'سارة', 'مريم', 'فاطمة', 'علي', 'حسن', '—'];
    final members = [
      for (var i = 0; i < names.length; i++) Member(uid: 'u$i', role: i == 0 ? 'admin' : 'member', slot: i, name: names[i], points: 10),
    ];
    final statuses = ['done', 'done', 'in_progress', 'pending', 'done', 'late', 'in_progress', 'done', 'pending', 'done', 'in_progress', 'pending'];
    final reads = [8, 8, 3, 0, 8, 2, 5, 8, 0, 8, 6, 0];
    final segs = <Segment>[];
    for (var s = 0; s < 30; s++) {
      final m = members.where((m) => currentSegment(g, m) == s).toList();
      if (m.isEmpty) {
        segs.add(Segment(seg: s, uid: null, status: s % 3 == 0 ? 'done' : 'open'));
      } else {
        final i = members.indexOf(m.first);
        segs.add(Segment(seg: s, uid: m.first.uid, status: statuses[i], read: reads[i]));
      }
    }
    final c = Cycle(
      number: 3, startedAt: DateTime(2026, 11, 6, 4), endsAt: DateTime(2026, 11, 13, 4),
      segments: segs, remainingQuarters: 120, khatmaComplete: false,
    );
    final portions = [
      for (final s in segs.where((s) => s.status == 'open'))
        Portion(id: 'p${s.seg}', cycle: 3, fromQuarter: s.seg * 8 + 1, toQuarter: s.seg * 8 + 8, quarterCount: 8, assignee: null, status: 'open', origin: 'empty'),
    ];
    final pdf = await buildGroupReport(t, 'ar', true, g, c, members, portions, true);
    File('build/report_sample.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(pdf);
  });
}
