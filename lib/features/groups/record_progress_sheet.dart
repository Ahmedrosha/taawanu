import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../services/groups_service.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';

/// الأدمن أو المساعد بيسجّل ورد عضو في الدورة الحالية (من غير نقاط للعضو).
Future<void> showRecordProgress(
  BuildContext context, {
  required Group group,
  required String memberUid,
  required String memberName,
  int? segmentFromQuarter,
}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final Assignment? a;
  try {
    a = await GroupsService.instance.memberAssignment(group.id, group.currentCycle, memberUid);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(t.actionFailed)));
    return;
  }
  if (!context.mounted) return;
  if (a == null || a.closed) {
    messenger.showSnackBar(SnackBar(content: Text(t.noPortionThisCycle)));
    return;
  }
  // الخانة دي ورد إضافي مع العضو، مش ورده الأساسي: بيتسجّل من الأوراد الإضافية.
  if (segmentFromQuarter != null && a.fromQuarter != segmentFromQuarter) {
    messenger.showSnackBar(SnackBar(content: Text(t.recordFromExtraPortions)));
    return;
  }
  final value = await _showSheet(
    context,
    title: t.recordProgressTitle(memberName),
    from: a.fromQuarter,
    to: a.toQuarter,
    current: a.quartersRead,
    // العضو خلّص بنفسه: الرجوع هيشيل نقاطه.
    selfDone: a.isDone && a.recordedBy == null,
  );
  if (value == null || value == a.quartersRead || !context.mounted) return;
  await runAction(context, () => GroupsService.instance.recordProgress(group.id, memberUid, value));
}

/// نفس الشاشة لورد إضافي.
Future<void> showRecordPortion(BuildContext context, {required Group group, required Portion portion, required String name}) async {
  final t = AppLocalizations.of(context);
  final current = portion.isDone ? portion.quarterCount : portion.quartersRead;
  final value = await _showSheet(
    context,
    title: t.recordProgressTitle(name),
    from: portion.fromQuarter,
    to: portion.toQuarter,
    current: current,
    selfDone: portion.isDone && portion.recordedBy == null && portion.assignee != null,
  );
  if (value == null || value == current || !context.mounted) return;
  await runAction(context, () => GroupsService.instance.recordPortion(group.id, portion.id, value));
}

Future<int?> _showSheet(
  BuildContext context, {
  required String title,
  required int from,
  required int to,
  required int current,
  required bool selfDone,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _RecordSheet(title: title, from: from, to: to, current: current, selfDone: selfDone),
  );
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.title, required this.from, required this.to, required this.current, required this.selfDone});

  final String title;
  final int from;
  final int to;
  final int current;
  final bool selfDone;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  late int _value = widget.current;

  int get _count => widget.to - widget.from + 1;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(rangeLabel(t, widget.from, widget.to), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InfoBanner(text: widget.selfDone ? t.undoSelfDoneNote : t.recordProgressNote),
            const SizedBox(height: 16),
            Text(t.quartersProgress(_value, _count), style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: _value.toDouble(),
              min: 0,
              max: _count.toDouble(),
              divisions: _count,
              label: '$_value',
              onChanged: (v) => setState(() => _value = v.round()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: widget.current == _count ? null : () => Navigator.pop(context, _count),
              child: Text(t.markWholeDone),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.current == 0 ? null : () => Navigator.pop(context, 0),
                    child: Text(t.reset),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, _value),
                    child: Text(t.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
