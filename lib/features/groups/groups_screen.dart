import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../services/prefs.dart';
import '../../theme/app_colors.dart';
import 'join_screen.dart';

/// حالة كل مجموعة اللي بنحتاجها للترتيب والكارت: المجموعة نفسها، ووردي في الدورة الحالية.
class _Stat {
  Group? group;
  Assignment? assignment;
}

/// بيتابع كل مجموعة من مجموعاتي ووردي فيها، عشان الكروت والترتيب يفضلوا محدّثين.
class _Stats extends ChangeNotifier {
  final _svc = GroupsService.instance;
  final stats = <String, _Stat>{};
  final _groupSubs = <String, StreamSubscription<Group?>>{};
  final _aSubs = <String, StreamSubscription<Assignment?>>{};
  final _aCycle = <String, int>{};

  void sync(List<MyGroup> groups) {
    final ids = groups.map((g) => g.id).toSet();
    for (final id in _groupSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _groupSubs.remove(id)?.cancel();
        _aSubs.remove(id)?.cancel();
        _aCycle.remove(id);
        stats.remove(id);
      }
    }
    for (final id in ids) {
      if (_groupSubs.containsKey(id)) continue;
      stats[id] = _Stat();
      _groupSubs[id] = _svc.group(id).listen((g) {
        stats[id]?.group = g;
        final cycle = (g?.isActive ?? false) ? g!.currentCycle : 0;
        if (_aCycle[id] != cycle) {
          _aCycle[id] = cycle;
          _aSubs.remove(id)?.cancel();
          stats[id]?.assignment = null;
          if (cycle > 0) {
            _aSubs[id] = _svc.myAssignment(id, cycle).listen((a) {
              stats[id]?.assignment = a;
              notifyListeners();
            });
          }
        }
        notifyListeners();
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    for (final s in _groupSubs.values) {
      s.cancel();
    }
    for (final s in _aSubs.values) {
      s.cancel();
    }
    super.dispose();
  }
}

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final Stream<List<MyGroup>> _groups = GroupsService.instance.myGroups();
  final _stats = _Stats();
  final _prefs = Prefs.instance;
  late String _role = _prefs.groupsRole;
  late String _type = _prefs.groupsType;
  late int _ward = _prefs.groupsWard;
  late String _sort = _prefs.groupsSort;
  late final List<String> _pinned = [..._prefs.pinnedGroups];
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _stats.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _filtered => _role != 'all' || _type != 'all' || _ward != 0 || _query.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _role = 'all';
      _type = 'all';
      _ward = 0;
      _query = '';
      _search.clear();
    });
    _prefs.setGroupsRole('all');
    _prefs.setGroupsType('all');
    _prefs.setGroupsWard(0);
  }

  void _togglePin(MyGroup g) {
    setState(() {
      if (!_pinned.remove(g.id)) _pinned.insert(0, g.id);
    });
    _prefs.setPinnedGroups(_pinned);
  }

  /// ترتيب "وردي لسه مخلصش": اللي ناقص فوق، بعدين اللي خلص، بعدين اللي مفيهوش ورد.
  int _pendingRank(MyGroup g) {
    final st = _stats.stats[g.id];
    final a = st?.assignment;
    if (a != null && !a.isDone && !a.closed) return 0;
    if (a != null) return 1;
    return 2;
  }

  List<MyGroup> _apply(List<MyGroup> all) {
    final q = _query.trim().toLowerCase();
    final list = all.where((g) {
      if (_role == 'manage' && !g.isManager) return false;
      if (_role == 'member' && g.isManager) return false;
      if (_type == 'private' && !g.isPrivate) return false;
      if (_type == 'public' && g.isPrivate) return false;
      if (_ward != 0 && g.wardQuarters != _ward) return false;
      if (q.isNotEmpty && !g.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    int byRecent(MyGroup a, MyGroup b) => (b.joinedAt ?? DateTime(2000)).compareTo(a.joinedAt ?? DateTime(2000));
    list.sort((a, b) {
      switch (_sort) {
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'size':
          final c = (_stats.stats[b.id]?.group?.memberCount ?? 0).compareTo(_stats.stats[a.id]?.group?.memberCount ?? 0);
          return c != 0 ? c : byRecent(a, b);
        case 'pending':
          final c = _pendingRank(a).compareTo(_pendingRank(b));
          return c != 0 ? c : byRecent(a, b);
        default:
          return byRecent(a, b);
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabGroups, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: t.explore, icon: const Icon(Icons.travel_explore), onPressed: () => context.push('/explore')),
          IconButton(tooltip: t.joinWithCode, icon: const Icon(Icons.link), onPressed: () => showJoinWithCode(context)),
          IconButton(tooltip: t.newGroup, icon: const Icon(Icons.add), onPressed: () => context.push('/create-group')),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<MyGroup>>(
        stream: _groups,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snap.data!;
          if (groups.isEmpty) return _EmptyState(onCreate: () => context.push('/create-group'));
          _stats.sync(groups);
          return ListenableBuilder(
            listenable: _stats,
            builder: (context, _) => _body(context, t, groups),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations t, List<MyGroup> groups) {
    final shown = _apply(groups);
    final pinned = shown.where((g) => _pinned.contains(g.id)).toList();
    final rest = shown.where((g) => !_pinned.contains(g.id)).toList();
    final managed = rest.where((g) => g.isManager).toList();
    final member = rest.where((g) => !g.isManager).toList();
    // الأقسام بتظهر بس لو فيه أكتر من نوع.
    final split = _role == 'all' && managed.isNotEmpty && member.isNotEmpty;

    final items = <Widget>[];
    void section(String title, List<MyGroup> list, {IconData? icon}) {
      if (list.isEmpty) return;
      if (title.isNotEmpty) {
        items.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: AppColors.accent), const SizedBox(width: 4)],
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
          ]),
        ));
      }
      for (final g in list) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _GroupCard(
            group: g,
            stat: _stats.stats[g.id],
            pinned: _pinned.contains(g.id),
            onLongPress: () => _pinSheet(context, g),
          ),
        ));
      }
    }

    if (pinned.isNotEmpty) section(t.pinnedSection, pinned, icon: Icons.push_pin);
    if (split) {
      section(t.filterManaged, managed);
      section(t.filterMember, member);
    } else {
      section(pinned.isNotEmpty ? t.tabGroups : '', rest);
    }

    final wards = groups.map((g) => g.wardQuarters).toSet().toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (groups.length > 6 || _query.isNotEmpty) ...[
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: t.searchGroups,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                        _query = '';
                        _search.clear();
                      })),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _filters(context, t, wards),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Text(t.noGroupsMatch, style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextButton(onPressed: _clearFilters, child: Text(t.clearFilters)),
            ]),
          )
        else
          ...items,
      ],
    );
  }

  Widget _filters(BuildContext context, AppLocalizations t, List<int> wards) {
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: FilterChip(
            label: Text(label),
            selected: on,
            showCheckmark: false,
            selectedColor: AppColors.navy,
            labelStyle: TextStyle(color: on ? Colors.white : AppColors.text, fontSize: 13),
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onTap(),
          ),
        );
    void setRole(String v) {
      final next = _role == v ? 'all' : v;
      setState(() => _role = next);
      _prefs.setGroupsRole(next);
    }

    void setType(String v) {
      final next = _type == v ? 'all' : v;
      setState(() => _type = next);
      _prefs.setGroupsType(next);
    }

    void setWard(int v) {
      final next = _ward == v ? 0 : v;
      setState(() => _ward = next);
      _prefs.setGroupsWard(next);
    }

    final sortLabel = switch (_sort) {
      'name' => t.sortName,
      'pending' => t.sortPending,
      'size' => t.sortSize,
      _ => t.sortRecent,
    };
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip(t.filterManaged, _role == 'manage', () => setRole('manage')),
              chip(t.filterMember, _role == 'member', () => setRole('member')),
              chip(t.typePrivateShort, _type == 'private', () => setType('private')),
              chip(t.typePublicShort, _type == 'public', () => setType('public')),
              if (wards.length > 1)
                for (final w in wards) chip(wardLabel(t, w), _ward == w, () => setWard(w)),
              if (_filtered)
                IconButton(tooltip: t.clearFilters, icon: const Icon(Icons.filter_alt_off, size: 20), onPressed: _clearFilters),
            ]),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: t.sortBy,
          initialValue: _sort,
          onSelected: (v) {
            setState(() => _sort = v);
            _prefs.setGroupsSort(v);
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'recent', child: Text(t.sortRecent)),
            PopupMenuItem(value: 'name', child: Text(t.sortName)),
            PopupMenuItem(value: 'pending', child: Text(t.sortPending)),
            PopupMenuItem(value: 'size', child: Text(t.sortSize)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sort, size: 18, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(sortLabel, style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _pinSheet(BuildContext context, MyGroup g) async {
    final t = AppLocalizations.of(context);
    final pinned = _pinned.contains(g.id);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          ListTile(
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(pinned ? t.unpinGroup : t.pinGroup),
            onTap: () => Navigator.pop(context, true),
          ),
        ]),
      ),
    );
    if (ok == true) _togglePin(g);
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.stat, required this.pinned, required this.onLongPress});

  final MyGroup group;
  final _Stat? stat;
  final bool pinned;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final g = stat?.group;
    final a = stat?.assignment;
    // حالة وردي في الدورة الحالية.
    String? status;
    Color statusColor = AppColors.textMuted;
    if (g != null) {
      if (!g.isActive) {
        status = t.groupNotStartedShort;
      } else if (a == null) {
        status = t.noPortionThisCycleShort;
      } else if (a.isDone) {
        status = t.myPortionDoneShort;
        statusColor = AppColors.statusDone;
      } else {
        status = t.myPortionProgress(a.quartersRead, a.quarterCount);
        statusColor = AppColors.accent;
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/group/${group.id}'),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(14)),
                child: Icon(group.isPrivate ? Icons.lock_outline : Icons.public, color: AppColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (pinned) ...[Icon(Icons.push_pin, size: 14, color: AppColors.accent), const SizedBox(width: 4)],
                      Expanded(child: Text(group.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      [
                        group.isPrivate ? t.typePrivateShort : t.typePublicShort,
                        wardLabel(t, group.wardQuarters),
                        if (g != null) t.groupMembersN(g.memberCount),
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 4),
                      Text(status, style: text.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  roleLabel(t, group.role),
                  style: text.labelSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: AppColors.sky, shape: BoxShape.circle),
              child: Icon(Icons.groups_outlined, size: 44, color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            Text(t.groupsEmptyTitle, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              t.groupsEmptyBody,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(t.newGroup),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => showJoinWithCode(context),
              icon: const Icon(Icons.link),
              label: Text(t.joinWithCode),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/explore'),
              icon: const Icon(Icons.travel_explore),
              label: Text(t.explore),
            ),
          ],
        ),
      ),
    );
  }
}
