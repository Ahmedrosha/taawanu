import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import 'mushaf_settings.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Stream<UserStats> _stats = UserService.instance.stats();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = AuthService.instance.user;
    final name = user?.displayName ?? t.defaultUserName;
    return Scaffold(
      appBar: AppBar(title: Text(t.tabProfile, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: StreamBuilder<UserStats>(
        stream: _stats,
        builder: (context, snap) {
          final s = snap.data ?? UserStats.fromMap(null);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Row(
                children: [
                  Avatar(name: name, photoUrl: user?.photoURL, size: 60),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        if (user?.email != null) Text(user!.email!, style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Expanded(child: StatTile(value: '${s.points}', label: t.totalPoints, onDark: true)),
                    Expanded(child: StatTile(value: '${s.streak}', label: t.streakCycles, onDark: true)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  _Kpi(title: t.commitment, value: s.commitment == null ? '—' : '${s.commitment}%', note: t.onTimeOf(s.onTimeCycles, s.totalCycles)),
                  _Kpi(title: t.longestStreakTitle, value: '${s.longestStreak}', note: t.streakCycles),
                  _Kpi(title: t.quartersReadLabel, value: '${s.quartersRead}', note: t.juzEquivalent((s.quartersRead / 8).toStringAsFixed(s.quartersRead % 8 == 0 ? 0 : 1))),
                  _Kpi(title: t.khatmasLabel, value: '${s.khatmasGroup + s.khatmasPersonal}', note: '${t.groupKhatmas(s.khatmasGroup)} · ${t.personalKhatmas(s.khatmasPersonal)}'),
                ],
              ),
              const SizedBox(height: 22),
              SectionTitle(t.badges),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final b in _badgeDefs(t)) _Badge(icon: b.$2, label: b.$3, earned: s.badges.contains(b.$1)),
                ],
              ),
              const SizedBox(height: 28),
              SectionTitle(t.mushafSettings),
              const SizedBox(height: 10),
              const MushafSettings(),
              const SizedBox(height: 28),
              SectionTitle(t.language),
              const SizedBox(height: 10),
              ValueListenableBuilder<Locale>(
                valueListenable: localeNotifier,
                builder: (context, locale, _) => SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'ar', label: Text(t.arabic)),
                    ButtonSegment(value: 'en', label: Text(t.english)),
                  ],
                  selected: {locale.languageCode},
                  onSelectionChanged: (sel) => setAppLocale(Locale(sel.first)),
                ),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: () => AuthService.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: Text(t.signOut),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final ok = await confirmDialog(context, title: t.deleteAccount, body: t.deleteAccountConfirm, destructive: true);
                  if (!ok || !context.mounted) return;
                  final done = await runAction(context, () => UserService.instance.deleteAccount());
                  if (done) await AuthService.instance.signOut();
                },
                child: Text(t.deleteAccount, style: const TextStyle(color: AppColors.statusLate)),
              ),
            ],
          );
        },
      ),
    );
  }

  List<(String, IconData, String)> _badgeDefs(AppLocalizations t) => [
        ('first_khatma', Icons.menu_book, t.badgeFirstKhatma),
        ('streak_4', Icons.local_fire_department_outlined, t.badgeStreak4),
        ('streak_12', Icons.whatshot, t.badgeStreak12),
        ('starter', Icons.star_outline, t.badgeStarter),
        ('rescuer', Icons.volunteer_activism_outlined, t.badgeRescuer),
        ('personal_khatma', Icons.workspace_premium_outlined, t.badgePersonal),
      ];
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.title, required this.value, required this.note});

  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.navy)),
          Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.earned});

  final IconData icon;
  final String label;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: earned ? const Color(0xFFFDF6E3) : const Color(0xFFF1F5F9),
              border: Border.all(color: earned ? AppColors.gold : const Color(0xFFCBD5E1), width: 2),
            ),
            child: Icon(icon, color: earned ? const Color(0xFF8A6A14) : const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: earned ? AppColors.text : AppColors.textMuted)),
        ],
      ),
    );
  }
}
