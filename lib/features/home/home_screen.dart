import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/auth_service.dart';
import '../../services/groups_service.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/name_dialog.dart';
import '../../widgets/ui.dart';
import '../groups/group_board_screen.dart' show ReadRequest, TimeLeftChip;
import '../prayer/next_prayer_tile.dart';
import '../shell/home_shell.dart' show shellNavKey;
import '../../widgets/tour.dart';
import '../../widgets/tour_texts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<UserStats> _stats = UserService.instance.stats().asBroadcastStream();
  late final Stream<List<MyGroup>> _groups = GroupsService.instance.myGroups();
  final _kStats = GlobalKey(), _kCard = GlobalKey(), _kRead = GlobalKey(), _kNew = GlobalKey();

  @override
  void initState() {
    super.initState();
    Tour.schedule(context, 'home', () => [
          TourStep(_kStats, tourText(context, 'home.stats')),
          TourStep(_kCard, tourText(context, 'home.card')),
          TourStep(_kRead, tourText(context, 'home.read')),
          TourStep(_kNew, tourText(context, 'home.newGroup')),
          TourStep(shellNavKey, tourText(context, 'home.nav'), padding: 0, radius: 0),
        ], delay: const Duration(milliseconds: 1400));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final authName = AuthService.instance.user?.displayName ?? '';
    return Scaffold(
      body: SafeArea(
        // مش ListView: القايمة الكسولة كانت بتشيل الكروت اللي برا الشاشة وترجع تحمّلها من الأول.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.greeting, style: TextStyle(color: AppColors.textMuted)),
            StreamBuilder<UserStats>(
              key: const ValueKey('greeting'),
              stream: _stats,
              builder: (context, snap) {
                final full = (snap.data?.name.isNotEmpty ?? false) ? snap.data!.name : authName;
                final name = full.split(' ').first;
                return Text(name.isEmpty ? t.defaultUserName : name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700));
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<UserStats>(
              key: const ValueKey('stats'),
              stream: _stats,
              builder: (context, snap) {
                final s = snap.data ?? UserStats.fromMap(null);
                return Container(
                  key: _kStats,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      Expanded(child: StatTile(value: '${s.streak}', label: t.streakCycles, onDark: true)),
                      Expanded(child: StatTile(value: '${s.points}', label: t.pointsWord, onDark: true)),
                      Expanded(child: StatTile(value: s.commitment == null ? '—' : '${s.commitment}%', label: t.commitment, onDark: true)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            const NextPrayerTile(),
            // الخانة دي بتفضل موجودة حتى بعد ما الكارت يتقفل، عشان اللي تحتها ميتحركش ويتبني من الأول
            // (بيانات "وردك الحالي" اشتراك بيتعمل مرة واحدة، ولو اتبنى من جديد كان بيفضل يحمّل).
            // اللي مالوش اسم: كارت يكتب منه اسمه، وبيختفي أول ما يكتبه.
            KeyedSubtree(
              key: const ValueKey('nameCard'),
              child: StreamBuilder<UserStats>(
                stream: _stats,
                builder: (context, snap) {
                  final name = snap.data?.name.trim();
                  if (name == null || (name.isNotEmpty && name != '—')) return const SizedBox.shrink();
                  return const Padding(padding: EdgeInsets.only(top: 12), child: _NameCard());
                },
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('guideCard'),
              child: Prefs.instance.guideCardDone
                  ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(top: 12), child: _GuideCard(onDone: () => setState(() {}))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                SectionTitle(t.yourPortions),
                const Spacer(),
                TextButton.icon(key: _kNew, onPressed: () => context.push('/create-group'), icon: const Icon(Icons.add), label: Text(t.newGroup)),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<MyGroup>>(
              key: const ValueKey('groups'),
              stream: _groups,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                final groups = snap.data!;
                if (groups.isEmpty) {
                  return AppCard(
                    child: Column(
                      children: [
                        Text(t.homeNoGroups, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: () => context.go('/groups'), child: Text(t.tabGroups)),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final (i, g) in groups.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        // المفتاح بالمجموعة: لو الترتيب اتغيّر، كل كارت يفضل بحالته وبياناته.
                        child: _HomeGroupCard(key: ValueKey(g.id), groupId: g.id, cardKey: i == 0 ? _kCard : null, readKey: i == 0 ? _kRead : null),
                      ),
                  ],
                );
              },
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _HomeGroupCard extends StatefulWidget {
  const _HomeGroupCard({super.key, required this.groupId, this.cardKey, this.readKey});

  final String groupId;

  /// مفاتيح الجولة التعريفية (لأول كارت بس).
  final GlobalKey? cardKey, readKey;

  @override
  State<_HomeGroupCard> createState() => _HomeGroupCardState();
}

class _HomeGroupCardState extends State<_HomeGroupCard> {
  late final Stream<Group?> _group = GroupsService.instance.group(widget.groupId);

  // ورد الدورة الحالية: اشتراك واحد لكل دورة، مش جديد مع كل تحديث في المجموعة.
  int? _cycleN;
  Stream<Assignment?>? _mine;

  Stream<Assignment?> _mineFor(Group g) {
    if (_cycleN != g.currentCycle || _mine == null) {
      _cycleN = g.currentCycle;
      _mine = GroupsService.instance.myAssignment(g.id, g.currentCycle);
    }
    return _mine!;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return KeyedSubtree(
      key: widget.cardKey,
      child: StreamBuilder<Group?>(
      stream: _group,
      builder: (context, gSnap) {
        final g = gSnap.data;
        if (g == null) return const SizedBox.shrink();
        final subtitle = '${g.isPrivate ? t.typePrivateShort : t.typePublicShort} · ${wardLabel(t, g.wardQuarters)}';
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/group/${g.id}'),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                          Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (g.isActive && g.nextCycleAt != null) TimeLeftChip(endsAt: g.nextCycleAt!),
                  ],
                ),
                const SizedBox(height: 12),
                if (!g.isActive)
                  Text(t.khatmaNotStarted, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600))
                else
                  StreamBuilder<Assignment?>(
                    stream: _mineFor(g),
                    builder: (context, aSnap) {
                      final a = aSnap.data;
                      // لسه بيحمّل: مكان فاضي بدل "ملكش ورد" اللي كان بيظهر لحظة.
                      if (a == null && aSnap.connectionState == ConnectionState.waiting) return const SizedBox(height: 60);
                      if (a == null) return Text(t.noPortionThisCycle, style: TextStyle(color: AppColors.textMuted));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(rangeLabel(t, a.fromQuarter, a.toQuarter),
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              if (a.isDone) StatusPill(label: t.portionDone, color: AppColors.statusDone),
                            ],
                          ),
                          RangeAyahsText(from: a.fromQuarter, to: a.toQuarter),
                          const SizedBox(height: 10),
                          ProgressLine(value: a.progress),
                          const SizedBox(height: 6),
                          Text(t.quartersProgress(a.quartersRead, a.quarterCount), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          if (!a.isDone && !a.closed) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: widget.readKey,
                              onPressed: () => context.push('/read', extra: ReadRequest.regular(group: g, assignment: a)),
                              icon: const Icon(Icons.menu_book_outlined),
                              label: Text(a.quartersRead > 0 ? t.continueReading : t.readNow),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}

/// كارت للمستخدم الجديد: بيفتح دليل الاستخدام، وبيختفي بعد ما يتفتح أو يتقفل.
/// كارت للي مالوش اسم: أعضاء مجموعته مش هيعرفوه غير لما يكتب اسمه.
class _NameCard extends StatelessWidget {
  const _NameCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Future<void> edit() async {
      final name = await showNameDialog(context, title: t.editName);
      if (name == null || !context.mounted) return;
      await runAction(context, () => UserService.instance.updateName(name), success: t.nameUpdated);
    }

    return Material(
      color: AppColors.goldTint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: edit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.badge_outlined, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.nameCardTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(t.nameCardBody, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                onPressed: edit,
                child: Text(t.nameCardButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      color: AppColors.goldTint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          context.push('/guide');
          await Prefs.instance.setGuideCardDone();
          onDone();
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
          child: Row(
            children: [
              Icon(Icons.menu_book_outlined, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.guideCardTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(t.guideCardBody, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close, size: 20),
                onPressed: () async {
                  await Prefs.instance.setGuideCardDone();
                  onDone();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
