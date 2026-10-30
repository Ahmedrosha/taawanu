import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<List<Group>> _groups = GroupsService.instance.explorePublic();
  CycleUnit? _filter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.explore, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _groups = GroupsService.instance.explorePublic());
          await _groups;
        },
        child: FutureBuilder<List<Group>>(
          future: _groups,
          builder: (context, snap) {
            if (snap.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(t.actionFailed))]);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = snap.data!;
            final groups = _filter == null ? all : all.where((g) => g.cycleUnit == _filter!.name).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(label: Text(t.all), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                    for (final u in CycleUnit.values)
                      ChoiceChip(label: Text(cycleUnitLabel(t, u)), selected: _filter == u, onSelected: (_) => setState(() => _filter = u)),
                  ],
                ),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(t.exploreEmpty, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
                  ),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                              StatusPill(label: t.freeSlots(g.slots - g.memberCount), color: AppColors.navy, light: true),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${wardLabel(t, g.wardQuarters)} · ${g.cycleCount == 1 ? '' : '${g.cycleCount} '}${cycleUnitLabel(t, CycleUnit.values.byName(g.cycleUnit))}',
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 10),
                          ProgressLine(value: g.memberCount / g.slots),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(t.membersCount(g.memberCount, g.slots), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              const Spacer(),
                              Text(t.khatmasCount(g.khatmasCompleted), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: () => context.push('/public/${g.id}'), child: Text(t.detailsAndJoin)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
