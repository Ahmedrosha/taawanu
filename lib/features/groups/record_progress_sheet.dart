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
  // العضو خلّص بنفسه وخد نقاطه: مفيش تعديل.
  if (a.isDone && a.recordedBy == null) {
    messenger.showSnackBar(SnackBar(content: Text(t.recordedBySelf(memberName))));
    return;
  }
  final value = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => _RecordSheet(name: memberName, assignment: a!),
  );
  if (value == null || value == a.quartersRead || !context.mounted) return;
  await runAction(context, () => GroupsService.instance.recordProgress(group.id, memberUid, value));
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.name, required this.assignment});

  final String name;
  final Assignment assignment;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  late int _value = widget.assignment.quartersRead;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a = widget.assignment;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.recordProgressTitle(widget.name), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(rangeLabel(t, a.fromQuarter, a.toQuarter), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InfoBanner(text: t.recordProgressNote),
            const SizedBox(height: 16),
            Text(t.quartersProgress(_value, a.quarterCount), style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: _value.toDouble(),
              min: 0,
              max: a.quarterCount.toDouble(),
              divisions: a.quarterCount,
              label: '$_value',
              onChanged: (v) => setState(() => _value = v.round()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, a.quarterCount),
              child: Text(t.markWholeDone),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 0),
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
