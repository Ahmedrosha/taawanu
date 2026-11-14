import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/prefs.dart';
import '../../services/groups_service.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/name_dialog.dart';
import '../../widgets/segment_picker.dart';
import 'assign_portions_screen.dart';
import 'record_progress_sheet.dart';
import 'group_messages.dart';
import 'group_report.dart';
import '../../widgets/tour.dart';
import '../../widgets/tour_texts.dart';
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

  // اشتراكات الدورة الحالية: بتتعمل مرة واحدة لكل دورة، مش مع كل إعادة بناء.
  int? _cycleN;
  late Stream<Cycle?> _cycle;
  late Stream<Assignment?> _mine;

  // الجولة التعريفية.
  final _kInvite = GlobalKey(), _kMenu = GlobalKey(), _kMembers = GlobalKey();
  final _cycleKeys = _CycleTourKeys();

  @override
  void initState() {
    super.initState();
    // بنستنى الخريطة: الجولة للمجموعة اللي بدأت بس، ولو لسه مبدأتش بتتأجل لحد ما تبدأ.
    Tour.schedule(context, 'board', () => _cycleKeys.map.currentContext == null ? const <TourStep>[] : [
          TourStep(_kInvite, tourText(context, 'board.invite'), radius: 24),
          TourStep(_kMenu, tourText(context, 'board.menu'), radius: 24),
          TourStep(_cycleKeys.mine, tourText(context, 'board.mine')),
          TourStep(_cycleKeys.map, tourText(context, 'board.map')),
          TourStep(_cycleKeys.extra, tourText(context, 'board.extra')),
          TourStep(_kMembers, tourText(context, 'board.members')),
        ], delay: const Duration(milliseconds: 1500));
  }

  void _ensureCycle(Group g) {
    if (_cycleN == g.currentCycle) return;
    _cycleN = g.currentCycle;
    _cycle = _svc.cycle(g.id, g.currentCycle);
    _mine = _svc.myAssignment(g.id, g.currentCycle);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<Group?>(
      stream: _group,
      builder: (context, gSnap) {
        if (gSnap.hasError) return ErrorScaffold(message: t.actionFailed);
        final g = gSnap.data;
        if (g == null) return const LoadingScaffold();
        _ensureCycle(g);
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
                      key: _kInvite,
                      tooltip: t.invite,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      onPressed: () => context.push('/group/${g.id}/invite', extra: g),
                    ),
                  KeyedSubtree(key: _kMenu, child: _BoardMenu(group: g, me: me)),
                ],
              ),
              // مش ListView: القايمة الكسولة كانت بتشيل الخريطة لما تنزل تحت، وترجع تبنيها فاضية فالشاشة "تنط" لفوق.
              body: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(group: g),
                  const SizedBox(height: 16),
                  if (!g.isActive)
                    _FormingCard(group: g, isManager: me?.isManager ?? false)
                  else
                    _ActiveCycle(group: g, members: members, portionsStream: _portions, cycleStream: _cycle, mineStream: _mine, me: me, tourKeys: _cycleKeys),
                  const SizedBox(height: 20),
                  KeyedSubtree(
                    key: _kMembers,
                    child: _MembersSection(group: g, members: members, me: me),
                  ),
                ],
                ),
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
              onPressed: () => context.push('/group/${g.id}/assign'),
              icon: const Icon(Icons.grid_view_rounded),
              label: Text(t.assignPortions),
            ),
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

/// مفاتيح الجولة التعريفية للعناصر اللي جوه الدورة.
class _CycleTourKeys {
  final mine = GlobalKey(), map = GlobalKey(), extra = GlobalKey();
}

class _ActiveCycle extends StatelessWidget {
  const _ActiveCycle({
    required this.group,
    required this.members,
    required this.portionsStream,
    required this.cycleStream,
    required this.mineStream,
    required this.me,
    required this.tourKeys,
  });

  final _CycleTourKeys tourKeys;

  final Group group;
  final List<Member> members;
  final Stream<List<Portion>> portionsStream;
  final Stream<Cycle?> cycleStream;
  final Stream<Assignment?> mineStream;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<Cycle?>(
      stream: cycleStream,
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
              stream: mineStream,
              builder: (context, aSnap) => _MyPortionCard(
                key: tourKeys.mine,
                group: group,
                assignment: aSnap.data,
                loading: !aSnap.hasData && aSnap.connectionState == ConnectionState.waiting,
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Portion>>(
              stream: portionsStream,
              builder: (context, pSnap) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cycle != null)
                    KeyedSubtree(
                      key: tourKeys.map,
                      child: _KhatmaMap(group: group, cycle: cycle, members: members, me: me, portions: pSnap.data ?? const []),
                    ),
                  if (cycle != null) _MessageButtons(group: group, cycle: cycle, members: members, me: me),
                  _DonePortions(
                    // المفتاح بالدورة: لما الدورة تتغير، الاشتراك يتجدد.
                    key: ValueKey(group.currentCycle),
                    group: group,
                    builder: (done) {
                      final portions = [...?pSnap.data, ...done]..sort((a, b) => a.fromQuarter.compareTo(b.fromQuarter));
                      if (portions.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _ExtraPortions(key: tourKeys.extra, group: group, portions: portions, members: members, me: me),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MyPortionCard extends StatelessWidget {
  const _MyPortionCard({super.key, required this.group, required this.assignment, required this.loading});

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
    this.personal = false,
    this.startSurah,
    this.startAyah,
  });

  /// المصحف الحر: كل القرآن من غير حدود ولا تسجيل لمجموعة. [surah]/[ayah]: افتح عندها، وإلا آخر مكان وقفت عنده.
  factory ReadRequest.personal({required String label, int? surah, int? ayah}) => ReadRequest(
        groupId: '_personal',
        groupName: label,
        fromQuarter: 1,
        toQuarter: 240,
        quartersRead: 240,
        personal: true,
        startSurah: surah,
        startAyah: ayah ?? (surah == null ? null : 1),
      );

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

  /// قراءة حرة (مش ورد في مجموعة).
  final bool personal;
  final int? startSurah;
  final int? startAyah;

  bool get isPortion => portionId != null;
  int get quarterCount => toQuarter - fromQuarter + 1;
}

Color segmentColor(String status) => switch (status) {
      'done' || 'late_done' => AppColors.statusDone,
      'in_progress' => AppColors.statusInProgress,
      'late' => AppColors.statusLate,
      'open' => Colors.transparent,
      _ => AppColors.statusPending,
    };

/// خانة لون الحالة: "متاح" فاضية بإطار بس، و"جاري" و"متأخر" بيتملوا أصفر على قد اللي اتقرا (fill من ٠ لـ١): الباقي رمادي للجاري وأحمر للمتأخر.
Widget segmentSwatch(String status, {double? width, double height = 10, double radius = 3, double fill = 1}) {
  final open = status == 'open';
  final partial = (status == 'in_progress' || status == 'late') && fill < 1;
  return Container(
    width: width,
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: partial ? (status == 'late' ? AppColors.statusLate : AppColors.statusPending) : segmentColor(status),
      borderRadius: BorderRadius.circular(radius),
      // "متاح" فاضي بإطار، و"اتأخر واتكمّل" أخضر بإطار أحمر.
      border: open
          ? Border.all(color: AppColors.mutedLine, width: 1)
          : status == 'late_done'
              ? Border.all(color: AppColors.statusLate, width: 1.5)
              : null,
    ),
    child: partial
        ? FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fill.clamp(0.0, 1.0),
            heightFactor: 1,
            child: ColoredBox(color: AppColors.statusInProgress),
          )
        : null,
  );
}

Color segmentTextColor(String status) => switch (status) {
      'done' || 'late' => Colors.white,
      'in_progress' => const Color(0xFF422006),
      _ => AppColors.textMuted,
    };

/// خريطة الختمة: الدورة الحالية، وبالأسهم الدورات اللي فاتت (المتأخر فيها أحمر).
class _KhatmaMap extends StatefulWidget {
  const _KhatmaMap({required this.group, required this.cycle, required this.members, required this.me, required this.portions});

  final Group group;

  /// الدورة الحالية.
  final Cycle cycle;
  final List<Member> members;
  final Member? me;

  /// الأوراد الإضافية المفتوحة (عشان "خده" من خريطة دورة فاتت).
  final List<Portion> portions;

  @override
  State<_KhatmaMap> createState() => _KhatmaMapState();
}

class _KhatmaMapState extends State<_KhatmaMap> {
  /// الدورة المعروضة (null = الحالية).
  int? _shown;

  Group get group => widget.group;
  int get _current => widget.cycle.number;
  int get _n => _shown ?? _current;

  /// الأدمن والمساعد: الضغط على ورد عضو بيفتح تسجيل ورده (في الدورة الحالية بس).
  bool get _canRecord => (widget.me?.isManager ?? false) && _n == _current;

  /// الدورات اللي فاتت: بتتحفظ أول ما تتحمل وبتفضل متحدثة، عشان القلب بينها يبقى فوري.
  final _cache = <int, Cycle>{};
  final _subs = <int, StreamSubscription<Cycle?>>{};

  /// آخر خريطة اتعرضت: بتفضل باهتة مكانها لحد ما الدورة الجديدة توصل.
  Cycle? _lastShown;

  void _ensure(int n) {
    if (n < 1 || n >= _current || _subs.containsKey(n)) return;
    _subs[n] = GroupsService.instance.cycle(group.id, n).listen((c) {
      if (c != null && mounted) setState(() => _cache[n] = c);
    }, onError: (_) {});
  }

  void _go(int n) {
    setState(() => _shown = n >= _current ? null : n);
    _ensure(n);
    _ensure(n - 1);
  }

  @override
  void initState() {
    super.initState();
    _ensure(_current - 1);
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _n == _current ? widget.cycle : _cache[_n];
    if (c != null) {
      _lastShown = c;
      return _card(context, c);
    }
    final last = _lastShown ?? widget.cycle;
    return _card(context, last, loading: true);
  }

  Widget _header(BuildContext context, Cycle? c, {bool loading = false}) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final isCurrent = _n == _current;
    String? sub;
    if (!isCurrent && c?.startedAt != null && c?.endsAt != null) {
      final f = DateFormat.MMMd(locale);
      sub = t.cycleRange(f.format(c!.startedAt!), f.format(c.endsAt!));
    }
    return Row(
      children: [
        IconButton(
          tooltip: t.olderCycle,
          onPressed: _n > 1 ? () => _go(_n - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                isCurrent ? '${t.mapCycleTitle(_n)} ${t.currentCycleTag}' : t.mapCycleTitle(_n),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: t.newerCycle,
          onPressed: isCurrent ? null : () => _go(_n + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  /// فاضل أقل من ربع الدورة الحالية: اللي لسه مخلصش بيتلوّن أحمر.
  bool _warn(Cycle c) {
    if (_n != _current || c.startedAt == null || c.endsAt == null) return false;
    final total = c.endsAt!.difference(c.startedAt!);
    return DateTime.now().isAfter(c.endsAt!.subtract(total ~/ 4));
  }

  String _shownStatus(Segment s, bool warn) =>
      warn && s.uid != null && (s.status == 'pending' || s.status == 'in_progress') ? 'late' : s.status;

  Widget _card(BuildContext context, Cycle c, {bool loading = false}) {
    final t = AppLocalizations.of(context);
    final names = {
      for (final e in group.formerNames.entries) e.key: t.formerName(e.value),
      for (final m in widget.members) m.uid: m.name,
    };
    // نسبة الانتهاء: الأرباع اللي خلصت من الـ٢٤٠.
    final done = (240 - c.remainingQuarters).clamp(0, 240);
    final percent = (done * 100 / 240).round();
    final warn = _warn(c);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, loading ? null : c, loading: loading),
          AnimatedOpacity(
            opacity: loading ? 0.4 : 1,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: loading,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(t.khatmaPercent(percent), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusDone)),
          ),
          const SizedBox(height: 6),
          ProgressLine(value: done / 240),
          const SizedBox(height: 6),
          Text(t.tapJuzHint, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          _juzGrid(context, t, names, c, warn),
          if (warn) ...[
            const SizedBox(height: 8),
            Text(t.lateWarningNote, style: TextStyle(fontSize: 12, color: AppColors.statusLate)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final st in ['done', 'in_progress', 'pending', 'late', 'late_done', 'open'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    segmentSwatch(st, width: 14, fill: st == 'in_progress' ? 0.5 : 1),
                    const SizedBox(width: 4),
                    Text(segmentStatusLabel(t, st), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
            ],
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// الأوراد اللي في الجزء ده بالترتيب: (رقم الورد، عدد أرباعه جوه الجزء، الورد بيبدأ هنا؟).
  List<(int, int, bool)> _partsOf(int juz) {
    final w = group.wardQuarters;
    final parts = <(int, int, bool)>[];
    var q = juz * 8;
    final end = q + 8;
    while (q < end) {
      final seg = q ~/ w;
      final stop = ((seg + 1) * w).clamp(q + 1, end);
      parts.add((seg, stop - q, q == seg * w));
      q = stop;
    }
    return parts;
  }

  /// ٣٠ مربع (جزء لكل مربع)، وتحت رقمه أوراده بألوانها.
  /// لو الورد أكبر من جزء: خط على جنب الجزء اللي بيبدأ منه ورد جديد، وعلامة في الشريط مكان البداية.
  Widget _juzGrid(BuildContext context, AppLocalizations t, Map<String, String> names, Cycle c, bool warn) {
    final bySeg = {for (final s in c.segments) s.seg: s};
    final big = group.wardQuarters > 8;
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        for (var juz = 0; juz < 30; juz++)
          Builder(builder: (context) {
            final parts = _partsOf(juz);
            final startsWard = big && (juz * 8) % group.wardQuarters == 0;
            final bar = <Widget>[];
            var q = juz * 8;
            for (var k = 0; k < parts.length; k++) {
              final (seg, len, starts) = parts[k];
              final s = bySeg[seg];
              final st = s == null ? 'open' : _shownStatus(s, warn);
              // الجزء ده من الورد: الأرباع اللي اتقرت منه (الورد بيتقري بالترتيب).
              final offset = q - seg * group.wardQuarters;
              q += len;
              final fill = s?.read == null ? 1.0 : ((s!.read! - offset).clamp(0, len) / len);
              if (big && starts) {
                bar.add(Container(width: 2, height: 12, margin: const EdgeInsetsDirectional.only(end: 1.5), color: AppColors.text));
              } else if (k > 0) {
                bar.add(SizedBox(width: parts.length > 4 ? 1.5 : 2));
              }
              bar.add(Expanded(
                flex: len,
                child: segmentSwatch(st, height: 8, radius: 2, fill: fill),
              ));
            }
            return Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _juzSheet(context, juz, bySeg, names, warn),
                child: Stack(
                  children: [
                    if (startsWard)
                      PositionedDirectional(start: 0, top: 0, bottom: 0, child: Container(width: 3, color: AppColors.accent)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 4, 5, 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${juz + 1}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                          Row(crossAxisAlignment: CrossAxisAlignment.center, children: bar),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  /// الورد الإضافي اللي اتعمل من باقي ورد متأخر في الدورة دي (لو لسه موجود).
  Portion? _leftoverOf(Segment s) {
    final w = group.wardQuarters;
    final from = s.seg * w + 1, to = (s.seg + 1) * w;
    for (final p in widget.portions) {
      if (p.cycle == _n && p.fromQuarter >= from && p.fromQuarter <= to) return p;
    }
    return null;
  }

  /// أوراد الجزء: مين معاه كل ورد وحالته. الأدمن يدوس على ورد يسجّله. في الدورات اللي فاتت:
  /// الورد المتأخر بيبيّن راح فين، ولو محدش خده فيه "خده".
  Future<void> _juzSheet(BuildContext context, int juz, Map<int, Segment> bySeg, Map<String, String> names, bool warn) async {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    final picked = await showModalBottomSheet<Segment>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _n == _current ? t.juzLabel(juz + 1) : '${t.juzLabel(juz + 1)} · ${t.cycleN(_n)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final (seg, _, _) in _partsOf(juz))
              if (bySeg[seg] case final s?)
                Builder(builder: (context) {
                  final st = _shownStatus(s, warn);
                  final left = s.status == 'late' && _n != _current ? _leftoverOf(s) : null;
                  final recordable = _canRecord && s.uid != null && s.status != 'late';
                  return ListTile(
                    leading: segmentSwatch(st, width: 14, height: 14, radius: 4,
                        fill: s.read == null ? 1 : s.read! / group.wardQuarters),
                    title: Text(segmentLabel(t, s.seg, group.wardQuarters), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (s.uid != null) names[s.uid] ?? t.formerMember,
                      segmentStatusLabel(t, st),
                      if (s.read != null && s.status == 'late') t.quartersProgress(s.read!, group.wardQuarters),
                      if (left != null && left.assignee != null) t.assignedTo(names[left.assignee] ?? t.formerMember),
                      if (left != null && left.assignee == null) t.noneTookIt,
                    ].join(' · ')),
                    trailing: left != null && left.isOpen
                        ? TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              runAction(context, () => svc.claimPortion(group.id, left.id));
                            },
                            child: Text(t.takeThis),
                          )
                        : recordable
                            ? const Icon(Icons.edit_note)
                            : null,
                    onTap: recordable ? () => Navigator.pop(context, s) : null,
                  );
                }),
            if (_canRecord)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(t.tapToRecordHint, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) {
      await showRecordProgress(
        context,
        group: group,
        memberUid: picked.uid!,
        memberName: names[picked.uid] ?? '—',
        segmentFromQuarter: picked.seg * group.wardQuarters + 1,
      );
    }
  }
}

/// تحت الخريطة: تذكير المتأخرين (للإدارة) وراسل الإدارة (لأي عضو).
class _MessageButtons extends StatelessWidget {
  const _MessageButtons({required this.group, required this.cycle, required this.members, required this.me});

  final Group group;
  final Cycle cycle;
  final List<Member> members;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final manager = me?.isManager ?? false;
    final lateCount = cycle.segments
        .where((s) => s.uid != null && s.uid != me?.uid && s.status != 'done' && s.status != 'late' && s.status != 'late_done')
        .map((s) => s.uid)
        .toSet()
        .length;
    final otherManagers = members.any((m) => m.isManager && m.uid != me?.uid);
    if (!manager && !otherManagers) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (manager && !cycle.khatmaComplete)
            FilledButton.tonalIcon(
              onPressed: lateCount == 0 ? null : () => showLateReminder(context, group: group, lateCount: lateCount, endsAt: cycle.endsAt),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text('${t.remindLate} ($lateCount)'),
            ),
          if (otherManagers) ...[
            if (manager) const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showContactManagers(context, group: group, members: members, myUid: me?.uid),
              icon: const Icon(Icons.mail_outline),
              label: Text(t.contactManagers),
            ),
          ],
        ],
      ),
    );
  }
}

String segmentStatusLabel(AppLocalizations t, String status) => switch (status) {
      'done' => t.statusDone,
      'in_progress' => t.statusInProgress,
      'late' => t.statusLate,
      'late_done' => t.statusLateDone,
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

/// كارت ورد إضافي (في اللوحة وفي صفحة الدورات اللي فاتت).
class _PortionTile extends StatelessWidget {
  const _PortionTile({required this.group, required this.p, required this.members, required this.me, this.locked = false});

  final Group group;
  final Portion p;
  final List<Member> members;
  final Member? me;

  /// ورد خلص في ختمة اكتملت: مفيش رجوع فيه.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    final names = {
      for (final e in group.formerNames.entries) e.key: t.formerName(e.value),
      for (final m in members) m.uid: m.name,
    };
    return Padding(
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
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
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
                if ((me?.isManager ?? false) && !(p.isDone && locked))
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

/// الأوراد الإضافية في مجموعات: أورادي، المتاحة، اللي حد شغال فيها، واللي خلصت ومن دورات فاتت في سطور بتفتح صفحتها.
class _ExtraPortions extends StatelessWidget {
  const _ExtraPortions({super.key, required this.group, required this.portions, required this.members, required this.me});

  final Group group;
  final List<Portion> portions;
  final List<Member> members;
  final Member? me;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final uid = GroupsService.instance.uid;
    final cur = group.currentCycle;
    final mine = portions.where((p) => !p.isDone && p.assignee == uid).toList();
    final open = portions.where((p) => !p.isDone && p.assignee != uid && p.cycle >= cur && p.isOpen).toList();
    final busy = portions.where((p) => !p.isDone && p.assignee != uid && p.cycle >= cur && !p.isOpen).toList();
    final past = portions.where((p) => !p.isDone && p.assignee != uid && p.cycle < cur).length;
    final done = portions.where((p) => p.isDone).length;

    Widget section(String title, List<Portion> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            for (final p in list) _PortionTile(group: group, p: p, members: members, me: me),
          ],
        );

    Widget row(IconData icon, Color color, String title, Widget Function() page) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(icon, color: color),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(t.extraPortions),
        const SizedBox(height: 4),
        Text(t.extraPortionsBody, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        if (mine.isNotEmpty) section(t.myExtraPortions, mine),
        if (open.isNotEmpty) section(t.availablePortions, open),
        if (busy.isNotEmpty) section(t.inProgressPortions, busy),
        const SizedBox(height: 4),
        if (done > 0)
          row(Icons.check_circle_outline, AppColors.statusDone, t.donePortionsN(done),
              () => _DonePortionsScreen(group: group, members: members, me: me)),
        if (past > 0)
          row(Icons.history, AppColors.statusLate, t.pastLeftovers(past),
              () => _PastPortionsScreen(group: group, members: members, me: me)),
      ],
    );
  }
}

/// الأوراد الإضافية اللي خلصت في الدورة الحالية.
class _DonePortionsScreen extends StatefulWidget {
  const _DonePortionsScreen({required this.group, required this.members, required this.me});

  final Group group;
  final List<Member> members;
  final Member? me;

  @override
  State<_DonePortionsScreen> createState() => _DonePortionsScreenState();
}

class _DonePortionsScreenState extends State<_DonePortionsScreen> {
  late final Stream<List<Portion>> _portions = GroupsService.instance.donePortions(widget.group.id, widget.group.currentCycle);

  /// الدورات اللي ختمتها اكتملت (أوراد الختمة دي مفيهاش رجوع).
  final Map<int, bool> _complete = {};

  void _checkCycles(Iterable<int> cycles) {
    for (final c in cycles) {
      if (_complete.containsKey(c)) continue;
      _complete[c] = false;
      GroupsService.instance.cycle(widget.group.id, c).first.then((cy) {
        if (mounted && (cy?.khatmaComplete ?? false)) setState(() => _complete[c] = true);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.donePortionsTitle)),
      body: StreamBuilder<List<Portion>>(
        stream: _portions,
        builder: (context, snap) {
          final list = [...?snap.data]..sort((a, b) {
              final c = a.cycle.compareTo(b.cycle);
              return c != 0 ? c : a.fromQuarter.compareTo(b.fromQuarter);
            });
          _checkCycles(list.map((p) => p.cycle).toSet());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (!snap.hasData) const Center(child: CircularProgressIndicator()),
              for (final p in list)
                _PortionTile(group: widget.group, p: p, members: widget.members, me: widget.me, locked: _complete[p.cycle] ?? true),
            ],
          );
        },
      ),
    );
  }
}

/// أوراد متأخرة من دورات خلصت، مقسومة بالدورة. الإدارة تقدر تقفل أوراد دورة.
class _PastPortionsScreen extends StatefulWidget {
  const _PastPortionsScreen({required this.group, required this.members, required this.me});

  final Group group;
  final List<Member> members;
  final Member? me;

  @override
  State<_PastPortionsScreen> createState() => _PastPortionsScreenState();
}

class _PastPortionsScreenState extends State<_PastPortionsScreen> {
  late final Stream<List<Portion>> _portions = GroupsService.instance.activePortions(widget.group.id);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final g = widget.group;
    return Scaffold(
      appBar: AppBar(title: Text(t.pastLeftoversTitle)),
      body: StreamBuilder<List<Portion>>(
        stream: _portions,
        builder: (context, snap) {
          final uid = GroupsService.instance.uid;
          final past = (snap.data ?? const <Portion>[]).where((p) => p.cycle < g.currentCycle && p.assignee != uid).toList();
          final byCycle = <int, List<Portion>>{};
          for (final p in past) {
            byCycle.putIfAbsent(p.cycle, () => []).add(p);
          }
          final cycles = byCycle.keys.toList()..sort();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(t.pastLeftoversBody, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              if (!snap.hasData) const Center(child: CircularProgressIndicator()),
              for (final c in cycles) ...[
                Row(
                  children: [
                    Expanded(child: SectionTitle(t.cyclePortionsHeader(c, byCycle[c]!.length))),
                    if (widget.me?.isManager ?? false)
                      TextButton.icon(
                        onPressed: () async {
                          if (await confirmDialog(context, title: t.closeCycleLeftovers, body: t.closeCycleConfirm(c), destructive: true) &&
                              context.mounted) {
                            await runAction(context, () => GroupsService.instance.closeCyclePortions(g.id, c));
                          }
                        },
                        icon: const Icon(Icons.block, size: 18),
                        label: Text(t.closeCycleLeftovers),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final p in byCycle[c]!..sort((a, b) => a.fromQuarter.compareTo(b.fromQuarter)))
                  _PortionTile(group: g, p: p, members: widget.members, me: widget.me),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// عنوان الأعضاء وزرار الترتيب والقايمة.
class _MembersSection extends StatefulWidget {
  const _MembersSection({required this.group, required this.members, required this.me});

  final Group group;
  final List<Member> members;
  final Member? me;

  @override
  State<_MembersSection> createState() => _MembersSectionState();
}

class _MembersSectionState extends State<_MembersSection> {
  static const _sorts = ['points', 'name', 'oldest', 'newest', 'ward', 'status'];
  late String _sort = _sorts.contains(Prefs.instance.memberSort) ? Prefs.instance.memberSort : 'points';
  Stream<Cycle?>? _cycleStream;
  int? _cycleNo;

  String _label(AppLocalizations t, String s) => switch (s) {
        'name' => t.sortName,
        'oldest' => t.sortOldest,
        'newest' => t.sortNewest,
        'ward' => t.sortWard,
        'status' => t.sortStatus,
        _ => t.sortPoints,
      };

  /// ترتيب حالة القراءة: المتأخر، اللي لسه مبدأش، الجاري، اللي خلص.
  static int _statusRank(String? st) => switch (st) {
        'late' => 0,
        'pending' => 1,
        'in_progress' => 2,
        'done' || 'late_done' => 3,
        _ => 4,
      };

  List<Member> _sorted(Cycle? cycle) {
    final g = widget.group;
    final list = [...widget.members];
    final far = DateTime(9999);
    int byPoints(Member a, Member b) => b.points.compareTo(a.points);
    int byName(Member a, Member b) {
      if (a.hasNoName != b.hasNoName) return a.hasNoName ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    final status = {for (final sg in cycle?.segments ?? const <Segment>[]) if (sg.uid != null) sg.uid!: sg.status};
    list.sort((a, b) {
      final r = switch (_sort) {
        'name' => byName(a, b),
        'oldest' => (a.joinedAt ?? far).compareTo(b.joinedAt ?? far),
        'newest' => (b.joinedAt ?? DateTime(0)).compareTo(a.joinedAt ?? DateTime(0)),
        'ward' => currentSegment(g, a).compareTo(currentSegment(g, b)),
        'status' => _statusRank(status[a.uid]).compareTo(_statusRank(status[b.uid])),
        _ => byPoints(a, b),
      };
      return r != 0 ? r : byName(a, b);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final g = widget.group;
    final needCycle = _sort == 'status' && g.isActive;
    if (needCycle && (_cycleStream == null || _cycleNo != g.currentCycle)) {
      _cycleNo = g.currentCycle;
      _cycleStream = GroupsService.instance.cycle(g.id, g.currentCycle);
    }
    final header = Row(
      children: [
        Expanded(child: SectionTitle(t.members)),
        PopupMenuButton<String>(
          tooltip: t.sortBy,
          initialValue: _sort,
          onSelected: (v) {
            setState(() => _sort = v);
            Prefs.instance.setMemberSort(v);
          },
          itemBuilder: (_) => [
            for (final s in _sorts)
              if (s != 'status' || g.isActive) PopupMenuItem(value: s, child: Text(_label(t, s))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_label(t, _sort), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 4),
                Icon(Icons.swap_vert, size: 20, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
    Widget body(Cycle? c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            _MembersList(group: g, members: _sorted(c), me: widget.me),
          ],
        );
    if (!needCycle) return body(null);
    return StreamBuilder<Cycle?>(stream: _cycleStream, builder: (context, snap) => body(snap.data));
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
                [
                  if (members[i].hasNoName) t.noName else members[i].name,
                  if (members[i].uid == me?.uid) t.you,
                ].join(' '),
                style: TextStyle(fontWeight: FontWeight.w600, color: members[i].hasNoName ? AppColors.textMuted : null),
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
  // العضو يقدر يفتح اسمه عشان يغيّر ورده قبل بداية الختمة بس.
  bool _canOpen(Member target) => (me?.isManager ?? false) || _canManage(target) || (target.uid == me?.uid && !group.isActive);

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
            ListTile(title: Text(target.hasNoName ? t.noName : target.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (canManage)
              ListTile(leading: const Icon(Icons.badge_outlined), title: Text(t.editMemberName), onTap: () => Navigator.pop(context, 'rename')),
            if ((me?.isManager ?? false) && target.uid != me?.uid)
              ListTile(leading: const Icon(Icons.mail_outline), title: Text(t.sendMessage), onTap: () => Navigator.pop(context, 'message')),
            if (group.isActive && (me?.isManager ?? false))
              ListTile(leading: const Icon(Icons.edit_note), title: Text(t.recordProgress), onTap: () => Navigator.pop(context, 'record')),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: Text((me?.isManager ?? false) ? t.changePortion : t.changeMyPortion),
              onTap: () => Navigator.pop(context, 'move'),
            ),
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
      case 'message':
        await showComposeMessage(context, groupId: group.id, to: target.uid, title: t.messageTo(target.name));
      case 'record':
        await showRecordProgress(context, group: group, memberUid: target.uid, memberName: target.name);
      case 'move':
        await _move(context, target);
      case 'rename':
        final name = await showNameDialog(
          context,
          title: t.editMemberName,
          current: target.hasNoName ? '' : target.name,
          hint: t.memberNameHint,
        );
        if (name != null && context.mounted) {
          await runAction(context, () => svc.setMemberName(group.id, target.uid, name), success: t.nameUpdated);
        }
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
    // العضو بيغيّر ورده بنفسه.
    if (!(me?.isManager ?? false)) {
      await changeOwnPortion(context, group: group, me: target, members: members);
      return;
    }
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
    await changePortionFlow(context, group: group, member: target, segment: seg);
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
          case 'assign':
            context.push('/group/${group.id}/assign');
          case 'settings':
            context.push('/group/${group.id}/settings', extra: group);
          case 'report':
            await shareGroupReport(context, group);
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
        if (me?.isManager ?? false) PopupMenuItem(value: 'assign', child: Text(t.assignPortions)),
        if (me?.isManager ?? false) PopupMenuItem(value: 'report', child: Text(t.shareReport)),
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
