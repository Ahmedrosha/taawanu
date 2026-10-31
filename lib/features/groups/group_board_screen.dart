import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/segment_picker.dart';
import 'record_progress_sheet.dart';
import '../../widgets/ui.dart';

/// لوحة المجموعة: الدورة الحالية، وخريطة الختمة، ووردي، والأوراد الإضافية، والأعضاء.
class GroupBoardScreen extends StatefulWidget {
  const GroupBoardScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupBoardScreen> createState() => _GroupBoardScreenState();
}

class _GroupBoardScreenState extends State<GroupBoardScreen> {
  final _svc = GroupsService.instance;
  late final Stream<Group?> _group = _svc.group(widget.groupId);
  late final Stream<List<Member>> _members = _svc.members(widget.groupId);
  late final Stream<List<Portion>> _portions = _svc.activePortions(widget.groupId);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<Group?>(
      stream: _group,
      builder: (context, gSnap) {
        if (gSnap.hasError) return ErrorScaffold(message: t.actionFailed);
        final g = gSnap.data;
        if (g == null) return const LoadingScaffold();
        return StreamBuilder<List<Member>>(
          stream: _members,
          builder: (context, mSnap) {
            final members = mSnap.data ?? const <Member>[];
            final me = members.where((m) => m.uid == _svc.uid).firstOrNull;
            return Scaffold(
              appBar: AppBar(
                title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                actions: [
                  if (me?.isManager ?? false)
                    IconButton(
                      tooltip: t.invite,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      onPressed: () => context.push('/group/${g.id}/invite', extra: g),
                    ),
                  _BoardMenu(group: g, me: me),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _Header(group: g),
                  const SizedBox(height: 16),
                  if (!g.isActive)
                    _FormingCard(group: g, isManager: me?.isManager ?? false)
                  else
                    _ActiveCycle(group: g, members: members, portionsStream: _portions, me: me),
                  const SizedBox(height: 20),
                  SectionTitle(t.members),
                  const SizedBox(height: 8),
                  _MembersList(group: g, members: members, me: me),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final g = group;
    final cycle = g.cycleCount == 1
        ? cycleUnitLabel(t, CycleUnit.values.byName(g.cycleUnit))
        : '${g.cycleCount} ${cycleUnitLabel(t, CycleUnit.values.byName(g.cycleUnit))}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(child: StatTile(value: wardLabel(t, g.wardQuarters), label: t.wardWord, onDark: true)),
          Expanded(child: StatTile(value: cycle, label: t.cycleWord, onDark: true)),
          Expanded(child: StatTile(value: '${g.memberCount}/${g.slots}', label: t.membersWord, onDark: true)),
          Expanded(child: StatTile(value: '${g.khatmasCompleted}', label: t.khatmasLabel, onDark: true)),
        ],
      ),
    );
  }
}

class _FormingCard extends StatefulWidget {
  const _FormingCard({required this.group, required this.isManager});

  final Group group;
  final bool isManager;

  @override
  State<_FormingCard> createState() => _FormingCardState();
}

class _FormingCardState extends State<_FormingCard> {
  bool _busy = false;

  Future<void> _start() async {
    final t = AppLocalizations.of(context);
    final ok = await confirmDialog(context, title: t.startKhatma, body: t.startKhatmaConfirm);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, () => GroupsService.instance.startKhatma(widget.group.id));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final g = widget.group;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.groupForming, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(t.groupFormingBody(g.memberCount, g.slots), style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          if (widget.isManager) ...[
            FilledButton(onPressed: _busy ? null : _start, child: Text(t.startKhatma)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/group/${g.id}/invite', extra: g),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(t.invite),
            ),
          ] else
            Text(t.waitingForAdmin, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActiveCycle extends StatelessWidget {
  const _ActiveCycle({required this.group, required this.members, required this.portionsStream, required this.me});

  final Group group;
  final List<Member> members;
  final Stream<List<Portion>> portionsStream;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    return StreamBuilder<Cycle?>(
      stream: svc.cycle(group.id, group.currentCycle),
      builder: (context, cSnap) {
        final cycle = cSnap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SectionTitle(t.cycleN(group.currentCycle)),
                const Spacer(),
                if (cycle?.endsAt != null) TimeLeftChip(endsAt: cycle!.endsAt!),
              ],
            ),
            const SizedBox(height: 10),
            if (cycle?.khatmaComplete ?? false) ...[
              InfoBanner(text: t.khatmaCompleteBanner),
              const SizedBox(height: 10),
            ],
            StreamBuilder<Assignment?>(
              stream: svc.myAssignment(group.id, group.currentCycle),
              builder: (context, aSnap) => _MyPortionCard(group: group, assignment: aSnap.data, loading: !aSnap.hasData && aSnap.connectionState == ConnectionState.waiting),
            ),
            const SizedBox(height: 16),
            if (cycle != null) _KhatmaMap(group: group, cycle: cycle, members: members, me: me),
            StreamBuilder<List<Portion>>(
              stream: portionsStream,
              builder: (context, pSnap) => _DonePortions(
                // المفتاح بالدورة: لما الدورة تتغير، الاشتراك يتجدد.
                key: ValueKey(group.currentCycle),
                group: group,
                builder: (done) {
                  final portions = [...?pSnap.data, ...done]..sort((a, b) => a.fromQuarter.compareTo(b.fromQuarter));
                  if (portions.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: _ExtraPortions(group: group, portions: portions, members: members, me: me),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MyPortionCard extends StatelessWidget {
  const _MyPortionCard({required this.group, required this.assignment, required this.loading});

  final Group group;
  final Assignment? assignment;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final a = assignment;
    if (loading) return const AppCard(child: Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())));
    if (a == null) {
      return AppCard(child: Text(t.noPortionThisCycle, style: TextStyle(color: AppColors.textMuted)));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.yourPortion, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  rangeLabel(t, a.fromQuarter, a.toQuarter),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
              if (a.isDone) StatusPill(label: t.portionDone, color: AppColors.statusDone),
            ],
          ),
          if (a.recordedBy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(t.recordedByAdminNote, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          RangeAyahsText(from: a.fromQuarter, to: a.toQuarter),
          const SizedBox(height: 12),
          ProgressLine(value: a.progress),
          const SizedBox(height: 6),
          Text(t.quartersProgress(a.quartersRead, a.quarterCount), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          if (!a.isDone && !a.closed) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => context.push('/read', extra: ReadRequest.regular(group: group, assignment: a)),
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(a.quartersRead > 0 ? t.continueReading : t.readNow),
            ),
          ] else if (a.isDone && !a.closed) ...[
            // الورد خلص: يقدر يفتحه تاني (ومنه يتراجع لو سجّل بالغلط).
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/read', extra: ReadRequest.regular(group: group, assignment: a)),
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(t.open),
            ),
          ],
        ],
      ),
    );
  }
}

/// بيانات فتح القارئ: ورد عادي أو ورد إضافي.
class ReadRequest {
  const ReadRequest({
    required this.groupId,
    required this.groupName,
    required this.fromQuarter,
    required this.toQuarter,
    required this.quartersRead,
    this.portionId,
  });

  factory ReadRequest.regular({required Group group, required Assignment assignment}) => ReadRequest(
        groupId: group.id,
        groupName: group.name,
        fromQuarter: assignment.fromQuarter,
        toQuarter: assignment.toQuarter,
        quartersRead: assignment.quartersRead,
      );

  factory ReadRequest.portion({required Group group, required Portion portion}) => ReadRequest(
        groupId: group.id,
        groupName: group.name,
        fromQuarter: portion.fromQuarter,
        toQuarter: portion.toQuarter,
        quartersRead: portion.isDone ? portion.quarterCount : portion.quartersRead,
        portionId: portion.id,
      );

  final String groupId;
  final String groupName;
  final int fromQuarter;
  final int toQuarter;
  final int quartersRead;
  final String? portionId;

  bool get isPortion => portionId != null;
  int get quarterCount => toQuarter - fromQuarter + 1;
}

Color segmentColor(String status) => switch (status) {
      'done' => AppColors.statusDone,
      'in_progress' => AppColors.statusInProgress,
      'late' => AppColors.statusLate,
      'open' => AppColors.statusEmpty,
      _ => AppColors.statusPending,
    };

Color segmentTextColor(String status) => switch (status) {
      'done' || 'late' => Colors.white,
      'in_progress' => const Color(0xFF422006),
      _ => AppColors.textMuted,
    };

class _KhatmaMap extends StatelessWidget {
  const _KhatmaMap({required this.group, required this.cycle, required this.members, required this.me});

  final Group group;
  final Cycle cycle;
  final List<Member> members;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final n = cycle.segments.length;
    final columns = n <= 6 ? 3 : n <= 10 ? 5 : n <= 30 ? 6 : n <= 60 ? 10 : n <= 120 ? 12 : 16;
    final showNumbers = n <= 60;
    final names = {for (final m in members) m.uid: m.name};
    final canRecord = me?.isManager ?? false;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.khatmaMap, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (canRecord) ...[
            const SizedBox(height: 2),
            Text(t.tapToRecordHint, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: showNumbers ? 6 : 3,
            crossAxisSpacing: showNumbers ? 6 : 3,
            childAspectRatio: showNumbers ? 1.1 : 1,
            children: [
              for (final s in cycle.segments)
                Tooltip(
                  message: '${rangeLabel(t, s.seg * group.wardQuarters + 1, (s.seg + 1) * group.wardQuarters)}'
                      ' · ${segmentStatusLabel(t, s.status)}${s.uid != null ? ' · ${names[s.uid] ?? ''}' : ''}',
                  child: GestureDetector(
                    // الأدمن والمساعد: الضغط على خانة عضو بيفتح تسجيل ورده.
                    onTap: canRecord && s.uid != null && s.status != 'late'
                        ? () => showRecordProgress(
                              context,
                              group: group,
                              memberUid: s.uid!,
                              memberName: names[s.uid] ?? '—',
                              segmentFromQuarter: s.seg * group.wardQuarters + 1,
                            )
                        : null,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: segmentColor(s.status),
                        borderRadius: BorderRadius.circular(showNumbers ? 8 : 3),
                        border: s.status == 'open' ? Border.all(color: AppColors.mutedLine) : null,
                      ),
                      child: showNumbers
                          ? Text('${s.seg + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: segmentTextColor(s.status)))
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final st in ['done', 'in_progress', 'pending', 'late', 'open'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: segmentColor(st), borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 4),
                    Text(segmentStatusLabel(t, st), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String segmentStatusLabel(AppLocalizations t, String status) => switch (status) {
      'done' => t.statusDone,
      'in_progress' => t.statusInProgress,
      'late' => t.statusLate,
      'open' => t.statusOpen,
      _ => t.statusPending,
    };

/// الأوراد الإضافية اللي خلصت في الدورة الحالية.
class _DonePortions extends StatefulWidget {
  const _DonePortions({super.key, required this.group, required this.builder});

  final Group group;
  final Widget Function(List<Portion> done) builder;

  @override
  State<_DonePortions> createState() => _DonePortionsState();
}

class _DonePortionsState extends State<_DonePortions> {
  late final Stream<List<Portion>> _done = GroupsService.instance.donePortions(widget.group.id, widget.group.currentCycle);

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Portion>>(
        stream: _done,
        builder: (context, snap) => widget.builder(snap.data ?? const []),
      );
}

class _ExtraPortions extends StatelessWidget {
  const _ExtraPortions({required this.group, required this.portions, required this.members, required this.me});

  final Group group;
  final List<Portion> portions;
  final List<Member> members;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    final names = {for (final m in members) m.uid: m.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(t.extraPortions),
        const SizedBox(height: 4),
        Text(t.extraPortionsBody, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        for (final p in portions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // الورد اللي خلص: أخضر فاتح.
                color: p.isDone ? AppColors.doneTint : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.isDone ? AppColors.doneBorder : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (p.isDone) ...[
                        Icon(Icons.check_circle, color: AppColors.statusDone, size: 22),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rangeLabel(t, p.fromQuarter, p.toQuarter), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(
                              [
                                t.cycleN(p.cycle),
                                if (p.isDone) t.portionDone else if (p.isOpen) t.statusOpen,
                                if (p.assignee != null) t.assignedTo(names[p.assignee] ?? '—'),
                                if (p.recordedBy != null) t.recordedByAdminNote,
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (p.isOpen)
                        TextButton(
                          onPressed: () => runAction(context, () => svc.claimPortion(group.id, p.id)),
                          child: Text(t.take),
                        )
                      else if (p.assignee == svc.uid)
                        FilledButton.tonal(
                          // الثيم بيخلي الزرار بعرض الشاشة، وهنا جوه صف فلازم عرض محدود.
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                          onPressed: () => context.push('/read', extra: ReadRequest.portion(group: group, portion: p)),
                          child: Text(p.isDone ? t.open : (p.quartersRead > 0 ? t.continueReading : t.readNow)),
                        ),
                      if (me?.isManager ?? false)
                        IconButton(
                          tooltip: t.assignToMember,
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _manage(context, p, names),
                        ),
                    ],
                  ),
                  if (!p.isDone && p.quartersRead > 0) ...[
                    const SizedBox(height: 10),
                    ProgressLine(value: p.progress),
                    const SizedBox(height: 4),
                    Text(t.quartersProgress(p.quartersRead, p.quarterCount), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _manage(BuildContext context, Portion p, Map<String, String> names) async {
    final t = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(leading: const Icon(Icons.edit_note), title: Text(t.recordProgress), onTap: () => Navigator.pop(context, '#record')),
            if (!p.isDone) ...[
              ListTile(leading: const Icon(Icons.volunteer_activism_outlined), title: Text(t.makeOpen), onTap: () => Navigator.pop(context, '')),
              const Divider(height: 1),
              for (final m in members)
                ListTile(leading: const Icon(Icons.person_outline), title: Text(m.name), onTap: () => Navigator.pop(context, m.uid)),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == '#record') {
      await showRecordPortion(context, group: group, portion: p, name: p.assignee != null ? (names[p.assignee] ?? '—') : t.extraPortions);
      return;
    }
    await runAction(context, () => GroupsService.instance.assignPortion(group.id, p.id, choice.isEmpty ? null : choice));
  }
}

class _MembersList extends StatelessWidget {
  const _MembersList({required this.group, required this.members, required this.me});

  final Group group;
  final List<Member> members;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(name: members[i].name, photoUrl: members[i].photoUrl),
              title: Text(
                members[i].uid == me?.uid ? '${members[i].name} ${t.you}' : members[i].name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  segmentLabel(t, currentSegment(group, members[i]), group.wardQuarters),
                  // التغيير هيتطبّق من الدورة الجاية.
                  if (group.isActive && members[i].nowSegCycle == group.currentCycle)
                    t.fromNextCycle(segmentLabel(t, segmentForSlot(members[i].slot, group.currentCycle + 1, group.slots), group.wardQuarters)),
                  roleLabel(t, members[i].role),
                ].join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Text(t.pointsN(members[i].points), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
              onLongPress: _canOpen(members[i]) ? () => _manage(context, members[i]) : null,
              onTap: _canOpen(members[i]) ? () => _manage(context, members[i]) : null,
            ),
          ],
        ],
      ),
    );
  }

  /// المدير يقدر يغيّر جزء أي حد (حتى نفسه والأدمن)، والأدوار حسب _canManage.
  bool _canOpen(Member target) => (me?.isManager ?? false) || _canManage(target);

  bool _canManage(Member target) {
    final m = me;
    if (m == null || target.uid == m.uid || target.isAdmin) return false;
    if (m.isAdmin) return true;
    return m.isManager && target.role == 'member';
  }

  Future<void> _manage(BuildContext context, Member target) async {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    final isAdmin = me?.isAdmin ?? false;
    final canManage = _canManage(target);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(target.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (group.isActive)
              ListTile(leading: const Icon(Icons.edit_note), title: Text(t.recordProgress), onTap: () => Navigator.pop(context, 'record')),
            ListTile(leading: const Icon(Icons.swap_vert), title: Text(t.changePortion), onTap: () => Navigator.pop(context, 'move')),
            if (canManage && isAdmin && target.role == 'member')
              ListTile(leading: const Icon(Icons.shield_outlined), title: Text(t.makeAssistant), onTap: () => Navigator.pop(context, 'assistant')),
            if (canManage && isAdmin && target.role == 'assistant')
              ListTile(leading: const Icon(Icons.person_outline), title: Text(t.makeMember), onTap: () => Navigator.pop(context, 'member')),
            if (canManage && isAdmin)
              ListTile(leading: const Icon(Icons.star_outline), title: Text(t.makeAdmin), onTap: () => Navigator.pop(context, 'admin')),
            if (canManage)
              ListTile(
              leading: Icon(Icons.person_remove_outlined, color: AppColors.statusLate),
              title: Text(t.removeFromGroup, style: TextStyle(color: AppColors.statusLate)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'record':
        await showRecordProgress(context, group: group, memberUid: target.uid, memberName: target.name);
      case 'move':
        await _move(context, target);
      case 'assistant':
      case 'member':
        await runAction(context, () => svc.setRole(group.id, target.uid, action));
      case 'admin':
        if (await confirmDialog(context, title: t.makeAdmin, body: t.makeAdminConfirm(target.name)) && context.mounted) {
          await runAction(context, () => svc.transferAdmin(group.id, target.uid));
        }
      case 'remove':
        if (await confirmDialog(context, title: t.removeFromGroup, body: target.name, destructive: true) && context.mounted) {
          await runAction(context, () => svc.removeMember(group.id, target.uid));
        }
    }
  }
}

extension on _MembersList {
  /// اختيار جزء جديد للعضو. لو الجزء مع حد تاني بيتبادلوا.
  Future<void> _move(BuildContext context, Member target) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // الأرقام = ورد كل عضو في الدورة الحالية (أو الأولى قبل البداية).
    final holders = {for (final m in members) currentSegment(group, m): m.name};
    final seg = await showSegmentPicker(
      context,
      wardQuarters: group.wardQuarters,
      slots: group.slots,
      selected: currentSegment(group, target),
      holders: holders,
      note: group.isActive ? t.changePortionNoteActive : t.changePortionNote,
    );
    if (seg == null || !context.mounted) return;
    int? next;
    final ok = await runAction(context, () async => next = await GroupsService.instance.moveMember(group.id, target.uid, seg));
    if (ok && next != null) {
      messenger.showSnackBar(SnackBar(content: Text(t.moveAppliesNext(segmentLabel(t, next!, group.wardQuarters)))));
    }
  }
}

/// ورد العضو في الدورة الحالية (لو الأدمن غيّره بعد ما بدأ، بيفضل القديم لحد آخر الدورة).
int currentSegment(Group group, Member m) {
  final n = group.isActive ? group.currentCycle : 1;
  if (m.nowSegCycle == n && m.nowSeg != null) return m.nowSeg!;
  return segmentForSlot(m.slot, n, group.slots);
}

class _BoardMenu extends StatelessWidget {
  const _BoardMenu({required this.group, required this.me});

  final Group group;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'settings':
            context.push('/group/${group.id}/settings', extra: group);
          case 'leave':
            if (await confirmDialog(context, title: t.leaveGroup, body: t.leaveConfirm, destructive: true) && context.mounted) {
              final ok = await runAction(context, () => svc.leave(group.id));
              if (ok && context.mounted) context.go('/groups');
            }
          case 'delete':
            if (await confirmDialog(context, title: t.deleteGroup, body: t.deleteConfirm, destructive: true) && context.mounted) {
              final ok = await runAction(context, () => svc.deleteGroup(group.id));
              if (ok && context.mounted) context.go('/groups');
            }
        }
      },
      itemBuilder: (context) => [
        if (me?.isManager ?? false) PopupMenuItem(value: 'settings', child: Text(t.groupSettings)),
        if (me != null && !me!.isAdmin) PopupMenuItem(value: 'leave', child: Text(t.leaveGroup)),
        if (me?.isAdmin ?? false)
          PopupMenuItem(value: 'delete', child: Text(t.deleteGroup, style: TextStyle(color: AppColors.statusLate))),
      ],
    );
  }
}

/// "بتخلص بعد ٣ أيام".
class TimeLeftChip extends StatelessWidget {
  const TimeLeftChip({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final left = endsAt.difference(DateTime.now());
    final label = left.isNegative
        ? t.cycleEnded
        : left.inDays >= 1
            ? t.daysLeft(left.inDays)
            : t.hoursLeft(left.inHours.clamp(1, 24));
    final full = DateFormat.MMMEd(Localizations.localeOf(context).toLanguageTag()).add_jm().format(endsAt);
    return Tooltip(message: full, child: StatusPill(label: label, color: AppColors.accent, light: true));
  }
}
