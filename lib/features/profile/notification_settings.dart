import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/push_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../prayer/prayer_alerts.dart';
import '../prayer/prayer_controller.dart';
import '../prayer/prayer_screen.dart' show prayerName;
import '../prayer/prayer_times.dart';

/// إعدادات الإشعارات: الصلاة، الأذكار، الورد، الجمعة، وإشعارات المجموعات.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  Prefs get _p => Prefs.instance;
  static const _prayers = [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];
  static const _before = [0, 5, 10, 15, 30];

  /// بيطلب الإذن لما حاجة تتفتح. false لو الإشعارات مقفولة للتطبيق.
  Future<bool> _allow() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await PrayerAlerts.instance.requestPermission()) return true;
    messenger.showSnackBar(SnackBar(content: Text(t.notificationsDenied)));
    return false;
  }

  Future<void> _toggle(String key, bool on) async {
    if (on && !await _allow()) return;
    await _p.setReminderOn(key, on);
    if (mounted) setState(() {});
    await PrayerAlerts.instance.rescheduleReminders();
  }

  Future<void> _pickTime(String key) async {
    final m = _p.reminderMinutes(key);
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (picked == null) return;
    await _p.setReminderMinutes(key, picked.hour * 60 + picked.minute);
    if (mounted) setState(() {});
    await PrayerAlerts.instance.rescheduleReminders();
  }

  Future<void> _prayerChanged(Future<void> Function() change) async {
    await change();
    if (mounted) setState(() {});
    await PrayerAlerts.instance.reschedule();
  }

  Widget _reminder(String key, String title, {String? subtitle}) {
    final on = _p.reminderOn(key);
    final m = _p.reminderMinutes(key);
    final time = TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
          value: on,
          onChanged: (v) => _toggle(key, v),
        ),
        if (on)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _pickTime(key),
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(AppLocalizations.of(context).reminderAt(time)),
            ),
          ),
      ],
    );
  }

  Widget _section(IconData icon, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final hasLocation = PrayerController.instance.hasLocation;
    final alerts = _p.prayerAlerts;
    final enabled = _p.prayerAlertsFor;
    return Scaffold(
      appBar: AppBar(title: Text(t.notificationSettings, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _section(Icons.mosque_outlined, t.notifPrayer, [
            if (!hasLocation)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t.notifPrayerNeedsLocation, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              )
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.prayerAlerts),
                subtitle: Text(t.prayerAlertsHint, style: const TextStyle(fontSize: 12)),
                value: alerts,
                onChanged: (v) async {
                  if (v && !await _allow()) return;
                  await _prayerChanged(() => _p.setPrayerAlerts(v));
                },
              ),
              if (alerts) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in _prayers)
                      FilterChip(
                        label: Text(prayerName(t, p)),
                        selected: enabled.contains(p.name),
                        onSelected: (v) => _prayerChanged(() {
                          final next = {...enabled};
                          v ? next.add(p.name) : next.remove(p.name);
                          return _p.setPrayerAlertsFor(next);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(t.notifBeforePrayer, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in _before)
                      ChoiceChip(
                        label: Text(m == 0 ? t.notifBeforeNone : t.notifBeforeMinutes(m)),
                        selected: _p.prayerReminderMinutes == m,
                        onSelected: (_) => _prayerChanged(() => _p.setPrayerReminderMinutes(m)),
                      ),
                  ],
                ),
              ],
            ],
          ]),
          _section(Icons.auto_stories_outlined, t.notifAdhkar, [
            _reminder('adhkarMorning', t.notifAdhkarMorning),
            _reminder('adhkarEvening', t.notifAdhkarEvening),
            _reminder('adhkarSleep', t.notifAdhkarSleep),
          ]),
          _section(Icons.menu_book_outlined, t.notifWard, [
            _reminder('ward', t.notifWardDaily, subtitle: t.notifWardHint),
          ]),
          _section(Icons.event_outlined, t.notifFriday, [
            _reminder('kahf', t.notifKahf),
            _reminder('salawat', t.notifSalawat),
          ]),
          _section(Icons.groups_outlined, t.notifGroups, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.notifGroupsSwitch),
              subtitle: Text(t.notifGroupsHint, style: const TextStyle(fontSize: 12)),
              value: _p.groupPush,
              onChanged: (v) async {
                await PushService.instance.setEnabled(v);
                if (mounted) setState(() {});
              },
            ),
          ]),
          Text(t.notifLocalNote, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
