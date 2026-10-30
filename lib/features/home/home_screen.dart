import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/auth_service.dart';
import '../../services/groups_service.dart';
import '../../services/quran_repository.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../groups/group_board_screen.dart' show ReadRequest, TimeLeftChip;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<UserStats> _stats = UserService.instance.stats();
  late final Stream<List<MyGroup>> _groups = GroupsService.instance.myGroups();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name = AuthService.instance.user?.displayName?.split(' ').first ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text(t.greeting, style: const TextStyle(color: AppColors.textMuted)),
            Text(name.isEmpty ? t.defaultUserName : name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            StreamBuilder<UserStats>(
              stream: _stats,
              builder: (context, snap) {
                final s = snap.data ?? UserStats.fromMap(null);
                return Container(
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
            const SizedBox(height: 20),
            Row(
              children: [
                SectionTitle(t.yourPortions),
                const Spacer(),
                TextButton.icon(onPressed: () => context.push('/create-group'), icon: const Icon(Icons.add), label: Text(t.newGroup)),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<MyGroup>>(
              stream: _groups,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                final groups = snap.data!;
                if (groups.isEmpty) {
                  return AppCard(
                    child: Column(
                      children: [
                        Text(t.homeNoGroups, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: () => context.go('/groups'), child: Text(t.tabGroups)),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final g in groups) Padding(padding: const EdgeInsets.only(bottom: 12), child: _HomeGroupCard(groupId: g.id)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGroupCard extends StatefulWidget {
  const _HomeGroupCard({required this.groupId});

  final String groupId;

  @override
  State<_HomeGroupCard> createState() => _HomeGroupCardState();
}

class _HomeGroupCardState extends State<_HomeGroupCard> {
  late final Stream<Group?> _group = GroupsService.instance.group(widget.groupId);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<Group?>(
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
                          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    if (g.isActive && g.nextCycleAt != null) TimeLeftChip(endsAt: g.nextCycleAt!),
                  ],
                ),
                const SizedBox(height: 12),
                if (!g.isActive)
                  Text(t.khatmaNotStarted, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600))
                else
                  StreamBuilder<Assignment?>(
                    stream: GroupsService.instance.myAssignment(g.id, g.currentCycle),
                    builder: (context, aSnap) {
                      final a = aSnap.data;
                      if (a == null) return Text(t.noPortionThisCycle, style: const TextStyle(color: AppColors.textMuted));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(rangeLabel(t, a.fromQuarter, a.toQuarter),
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              if (a.isDone) StatusPill(label: t.portionDone, color: AppColors.statusDone),
                            ],
                          ),
                          RangeAyahsText(from: a.fromQuarter, to: a.toQuarter),
                          const SizedBox(height: 10),
                          ProgressLine(value: a.progress),
                          const SizedBox(height: 6),
                          Text(t.quartersProgress(a.quartersRead, a.quarterCount), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          if (!a.isDone && !a.closed) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
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
    );
  }
}
