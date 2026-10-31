import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../services/groups_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/segment_picker.dart';
import '../../widgets/ui.dart';
import 'group_board_screen.dart' show currentSegment;

/// تغيير ورد عضو، مع رسالة تأكيد لو الورد مع حد أو حد فيهم كان قرا.
/// بيرجّع true لو التغيير اتعمل.
Future<bool> changePortionFlow(
  BuildContext context, {
  required Group group,
  required Member member,
  required int segment,
}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final svc = GroupsService.instance;
  try {
    final out = await svc.moveMember(group.id, member.uid, segment);
    if (out.needsConfirm) {
      if (!context.mounted) return false;
      final ok = await _confirmMove(context, group: group, member: member, segment: segment, out: out);
      if (!ok) return false;
      await svc.moveMember(group.id, member.uid, segment, confirm: true);
    }
    messenger.showSnackBar(SnackBar(content: Text(t.portionChanged)));
    return true;
  } on FirebaseFunctionsException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(switch (e.code) {
        'already-exists' => t.segmentTakenError,
        'failed-precondition' => t.alreadyStartedError,
        _ => t.actionFailed,
      }),
    ));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(t.actionFailed)));
  }
  return false;
}

Future<bool> _confirmMove(
  BuildContext context, {
  required Group group,
  required Member member,
  required int segment,
  required MoveOutcome out,
}) async {
  final t = AppLocalizations.of(context);
  final newLabel = segmentLabel(t, segment, group.wardQuarters);
  final oldLabel = segmentLabel(t, currentSegment(group, member), group.wardQuarters);
  final other = out.otherName;
  final title = other != null ? t.swapTitle(newLabel, other) : t.moveTitle;
  final body = other != null
      ? t.swapBody(member.name, newLabel, other, oldLabel)
      : out.volunteerName != null
          ? t.volunteerBody(out.volunteerName!, member.name)
          : t.moveBody(member.name, newLabel);
  final warnings = [
    if (out.myRead > 0) t.clearedWarning(member.name, out.myRead, out.quarterCount),
    if (other != null && out.otherRead > 0) t.clearedWarning(other, out.otherRead, out.quarterCount),
    if (out.volunteerName != null && out.volunteerRead > 0) t.clearedWarning(out.volunteerName!, out.volunteerRead, out.quarterCount),
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: const TextStyle(height: 1.6)),
          for (final w in warnings) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusLate.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(w, style: TextStyle(color: AppColors.statusLate, fontSize: 13, height: 1.5)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(other != null ? t.confirmSwap : t.confirm)),
      ],
    ),
  );
  return ok ?? false;
}

/// شاشة "توزيع الأوراد" للأدمن والمساعد: كل الأوراد وصاحب كل ورد،
/// والضغط على ورد بيختار مين ياخده. شغالة قبل بداية الختمة وبعدها.
class AssignPortionsScreen extends StatefulWidget {
  const AssignPortionsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<AssignPortionsScreen> createState() => _AssignPortionsScreenState();
}

class _AssignPortionsScreenState extends State<AssignPortionsScreen> {
  final _svc = GroupsService.instance;
  late final Stream<Group?> _group = _svc.group(widget.groupId);
  late final Stream<List<Member>> _members = _svc.members(widget.groupId);
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<Group?>(
      stream: _group,
      builder: (context, gSnap) {
        final g = gSnap.data;
        if (g == null) return const LoadingScaffold();
        return StreamBuilder<List<Member>>(
          stream: _members,
          builder: (context, mSnap) {
            final members = mSnap.data;
            if (members == null) return const LoadingScaffold();
            if (!g.isActive) return _scaffold(context, t, g, members, null);
            return StreamBuilder<Cycle?>(
              stream: _svc.cycle(g.id, g.currentCycle),
              builder: (context, cSnap) {
                if (!cSnap.hasData && cSnap.connectionState == ConnectionState.waiting) return const LoadingScaffold();
                return _scaffold(context, t, g, members, cSnap.data);
              },
            );
          },
        );
      },
    );
  }

  Widget _scaffold(BuildContext context, AppLocalizations t, Group g, List<Member> members, Cycle? cycle) {
    final names = {for (final m in members) m.uid: m.name};
    // صاحب كل ورد: من الدورة (فيها المتطوعين كمان)، أو من الخانات قبل البداية.
    final holder = <int, String>{};
    final status = <int, String>{};
    if (cycle != null) {
      for (final s in cycle.segments) {
        if (s.uid != null) holder[s.seg] = s.uid!;
        status[s.seg] = s.status;
      }
    } else {
      for (final m in members) {
        holder[currentSegment(g, m)] = m.uid;
      }
    }
    // عضو ملوش ورد: خانته في الدورة دي مع حد تاني (متطوع) أو فاضية.
    final unassigned = [
      for (final m in members)
        if (holder[currentSegment(g, m)] != m.uid) m,
    ];
    final ownSeg = {for (final m in members) m.uid: currentSegment(g, m)};

    Widget cell(int seg, String label) {
      final uid = holder[seg];
      final extra = uid != null && ownSeg[uid] != seg;
      final st = status[seg] ?? (uid == null ? 'open' : 'pending');
      final free = uid == null;
      final bg = free
          ? AppColors.surface
          : st == 'done'
              ? AppColors.doneTint
              : extra
                  ? AppColors.goldTint
                  : AppColors.sky;
      return Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: free ? AppColors.mutedLine : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _pick(context, g, members, seg, holder, unassigned),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (st == 'done') Icon(Icons.check_circle, size: 12, color: AppColors.statusDone),
                    if (st == 'in_progress') Icon(Icons.timelapse, size: 12, color: AppColors.statusInProgress),
                    if (st == 'done' || st == 'in_progress') const SizedBox(width: 2),
                    Flexible(
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                    ),
                  ],
                ),
                Text(
                  free ? t.statusOpen : (names[uid] ?? '—'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: free ? AppColors.textMuted : AppColors.accent),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.assignPortions, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(g.isActive ? '${g.name} · ${t.cycleN(g.currentCycle)}' : g.name,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (unassigned.isNotEmpty) ...[
              const SizedBox(height: 10),
              Material(
                color: AppColors.goldTint,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(t.membersWithoutPortion(unassigned.length)),
                      content: Text(unassigned.map((m) => m.name).join('\n')),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).okButtonLabel))],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.goldText, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t.membersWithoutPortion(unassigned.length), style: TextStyle(color: AppColors.goldText))),
                        Text(t.showWho, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(t.assignHint, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: SegmentGrid(
                scroll: null,
                wardQuarters: g.wardQuarters,
                slots: g.slots,
                wide: true,
                cell: cell,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    Group g,
    List<Member> members,
    int seg,
    Map<int, String> holder,
    List<Member> unassigned,
  ) async {
    final t = AppLocalizations.of(context);
    final current = holder[seg];
    final sorted = [...members]..sort((a, b) {
        final ua = unassigned.contains(a) ? 0 : 1;
        final ub = unassigned.contains(b) ? 0 : 1;
        if (ua != ub) return ua - ub;
        return currentSegment(g, a).compareTo(currentSegment(g, b));
      });
    final label = segmentLabel(t, seg, g.wardQuarters);
    final chosen = await showModalBottomSheet<Member>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(t.whoTakes(label), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (unassigned.isNotEmpty)
              Text(t.withoutPortionFirst, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            for (final m in sorted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(name: m.name, photoUrl: m.photoUrl, size: 36),
                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  unassigned.contains(m)
                      ? t.noPortionShort
                      : segmentLabel(t, currentSegment(g, m), g.wardQuarters),
                  style: TextStyle(
                    fontSize: 12,
                    color: unassigned.contains(m) ? AppColors.goldText : AppColors.textMuted,
                    fontWeight: unassigned.contains(m) ? FontWeight.w600 : null,
                  ),
                ),
                trailing: m.uid == current ? Text(t.currentHolder, style: TextStyle(color: AppColors.textMuted, fontSize: 12)) : null,
                onTap: m.uid == current && currentSegment(g, m) == seg ? null : () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    setState(() => _busy = true);
    await changePortionFlow(context, group: g, member: chosen, segment: seg);
    if (mounted) setState(() => _busy = false);
  }
}

/// العضو بيغيّر ورده بنفسه: لورد فاضي بس، وطول ما لسه مبدأش يقرا.
Future<void> changeOwnPortion(BuildContext context, {required Group group, required Member me, required List<Member> members}) async {
  final t = AppLocalizations.of(context);
  final taken = <int>{};
  if (group.isActive) {
    final cycle = await GroupsService.instance.cycle(group.id, group.currentCycle).first;
    for (final s in cycle?.segments ?? const <Segment>[]) {
      if (s.uid != null && s.uid != me.uid) taken.add(s.seg);
    }
  } else {
    for (final m in members) {
      if (m.uid != me.uid) taken.add(currentSegment(group, m));
    }
  }
  if (!context.mounted) return;
  final seg = await showSegmentPicker(
    context,
    wardQuarters: group.wardQuarters,
    slots: group.slots,
    selected: currentSegment(group, me),
    taken: taken,
    note: t.changeMyPortionNote,
  );
  if (seg == null || !context.mounted) return;
  await changePortionFlow(context, group: group, member: me, segment: seg);
}
