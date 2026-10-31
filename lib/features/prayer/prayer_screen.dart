import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../../services/prefs.dart';
import 'prayer_alerts.dart';
import 'prayer_controller.dart';
import 'prayer_times.dart';
import 'qibla_screen.dart';

String prayerName(AppLocalizations t, Prayer p) => switch (p) {
      Prayer.fajr => t.prayerFajr,
      Prayer.sunrise => t.prayerSunrise,
      Prayer.dhuhr => t.prayerDhuhr,
      Prayer.asr => t.prayerAsr,
      Prayer.maghrib => t.prayerMaghrib,
      Prayer.isha => t.prayerIsha,
    };

String methodName(AppLocalizations t, PrayerMethodId m) => switch (m) {
      PrayerMethodId.ummAlQura => t.methodUmmAlQura,
      PrayerMethodId.egypt => t.methodEgypt,
      PrayerMethodId.gulf => t.methodGulf,
      PrayerMethodId.kuwait => t.methodKuwait,
      PrayerMethodId.qatar => t.methodQatar,
      PrayerMethodId.mwl => t.methodMwl,
      PrayerMethodId.karachi => t.methodKarachi,
      PrayerMethodId.isna => t.methodIsna,
      PrayerMethodId.turkey => t.methodTurkey,
      PrayerMethodId.singapore => t.methodSingapore,
    };

/// "بعد ٤٥ دقيقة" / "بعد ساعتين و١٠ دقايق".
String timeUntil(AppLocalizations t, Duration d) {
  final mins = d.inMinutes + 1;
  if (mins < 60) return t.inMinutes(mins);
  return t.inHoursMinutes(mins ~/ 60, mins % 60);
}

String formatTime(BuildContext context, DateTime utc) =>
    DateFormat.jm(Localizations.localeOf(context).toLanguageTag()).format(utc.toLocal());

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  final _c = PrayerController.instance;
  Timer? _tick;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_refresh);
    // تحديث العد التنازلي كل ٣٠ ثانية.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _locate() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final r = await _c.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    final msg = switch (r) {
      LocateResult.ok => null,
      LocateResult.serviceOff => t.locationServiceOff,
      LocateResult.denied => t.locationDenied,
      LocateResult.deniedForever => t.locationDeniedForever,
      LocateResult.failed => t.locationFailed,
    };
    if (msg != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        action: r == LocateResult.deniedForever ? SnackBarAction(label: t.openSettings, onPressed: _c.openSettings) : null,
      ));
    }
  }

  Future<void> _pickCity() async {
    final t = AppLocalizations.of(context);
    final ar = Localizations.localeOf(context).languageCode != 'en';
    final city = await showModalBottomSheet<City>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (context, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t.chooseCity, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  for (final c in cities)
                    ListTile(title: Text(ar ? c.ar : c.en), onTap: () => Navigator.pop(context, c)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (city != null) await _c.setCity(city);
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _PrayerSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabPrayer, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_c.hasLocation) IconButton(tooltip: t.prayerSettings, icon: const Icon(Icons.tune), onPressed: _settings),
        ],
      ),
      body: !_c.hasLocation
          ? _NoLocation(locating: _locating, onLocate: _locate, onPickCity: _pickCity)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _LocationRow(
                  name: _c.placeName(locale) ?? t.currentLocation,
                  locating: _locating,
                  onLocate: _locate,
                  onPickCity: _pickCity,
                ),
                const SizedBox(height: 12),
                _NextPrayerCard(controller: _c),
                const SizedBox(height: 12),
                _TodayTimes(controller: _c),
                const SizedBox(height: 12),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.explore_outlined, color: AppColors.accent),
                    title: Text(t.qiblaDirection, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(t.qiblaBearing(qiblaBearing(_c.lat, _c.lng).round())),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QiblaScreen())),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${methodName(t, _c.method)} · ${_c.asrHanafi ? t.asrHanafi : t.asrStandard}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
    );
  }
}

class _NoLocation extends StatelessWidget {
  const _NoLocation({required this.locating, required this.onLocate, required this.onPickCity});

  final bool locating;
  final VoidCallback onLocate;
  final VoidCallback onPickCity;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mosque_outlined, size: 64, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(t.prayerNeedLocation, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            Text(t.locationPrivacyNote, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: locating ? null : onLocate,
              icon: locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location),
              label: Text(t.useMyLocation),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: onPickCity, icon: const Icon(Icons.location_city), label: Text(t.chooseCity)),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.name, required this.locating, required this.onLocate, required this.onPickCity});

  final String name;
  final bool locating;
  final VoidCallback onLocate;
  final VoidCallback onPickCity;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(Icons.place_outlined, size: 20, color: AppColors.accent),
        const SizedBox(width: 6),
        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
          tooltip: t.useMyLocation,
          onPressed: locating ? null : onLocate,
          icon: locating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 20),
        ),
        IconButton(tooltip: t.chooseCity, onPressed: onPickCity, icon: const Icon(Icons.edit_location_alt_outlined, size: 20)),
      ],
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({required this.controller});

  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final (p, at) = controller.next(now);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.nextPrayer, style: const TextStyle(color: Color(0xFFDBEAFE), fontSize: 13)),
                const SizedBox(height: 4),
                Text(prayerName(t, p), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(timeUntil(t, at.difference(now.toUtc())), style: const TextStyle(color: Color(0xFFDBEAFE))),
              ],
            ),
          ),
          Text(formatTime(context, at), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TodayTimes extends StatelessWidget {
  const _TodayTimes({required this.controller});

  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = controller.timesFor(now);
    final (nextP, nextAt) = controller.next(now);
    final isNextToday = nextAt.toLocal().day == now.day;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (final p in Prayer.values) ...[
            if (p != Prayer.fajr) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    p == Prayer.sunrise ? Icons.wb_twilight : Icons.access_time,
                    size: 18,
                    color: isNextToday && p == nextP ? AppColors.accent : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      prayerName(t, p),
                      style: TextStyle(
                        fontWeight: isNextToday && p == nextP ? FontWeight.w700 : FontWeight.w500,
                        color: p == Prayer.sunrise ? AppColors.textMuted : AppColors.text,
                      ),
                    ),
                  ),
                  Text(
                    formatTime(context, today[p]),
                    style: TextStyle(
                      fontWeight: isNextToday && p == nextP ? FontWeight.w700 : FontWeight.w500,
                      color: isNextToday && p == nextP ? AppColors.accent : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrayerSettingsSheet extends StatefulWidget {
  const _PrayerSettingsSheet();

  @override
  State<_PrayerSettingsSheet> createState() => _PrayerSettingsSheetState();
}

class _PrayerSettingsSheetState extends State<_PrayerSettingsSheet> {
  final _c = PrayerController.instance;
  Prefs get _prefs => Prefs.instance;

  Future<void> _toggleAlerts(bool on) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (on && !await PrayerAlerts.instance.requestPermission()) {
      messenger.showSnackBar(SnackBar(content: Text(t.notificationsDenied)));
      return;
    }
    await _prefs.setPrayerAlerts(on);
    if (mounted) setState(() {});
    await PrayerAlerts.instance.reschedule();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auto = defaultMethodFor(_c.lat, _c.lng);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.prayerSettings, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text(t.calculationMethod, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<PrayerMethodId?>(
              initialValue: _c.methodIsAuto ? null : _c.method,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: null, child: Text(t.methodAuto(methodName(t, auto)))),
                for (final m in PrayerMethodId.values) DropdownMenuItem(value: m, child: Text(methodName(t, m))),
              ],
              onChanged: (v) async {
                await _c.setMethod(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 16),
            Text(t.asrMethod, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(t.asrStandard)),
                ButtonSegment(value: true, label: Text(t.asrHanafi)),
              ],
              selected: {_c.asrHanafi},
              onSelectionChanged: (s) async {
                await _c.setAsrHanafi(s.first);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.prayerAlerts, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t.prayerAlertsHint, style: const TextStyle(fontSize: 12)),
              value: _prefs.prayerAlerts,
              onChanged: _toggleAlerts,
            ),
            if (_prefs.prayerAlerts) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha])
                    FilterChip(
                      label: Text(prayerName(t, p)),
                      selected: _prefs.prayerAlertsFor.contains(p.name),
                      onSelected: (on) async {
                        final set = {..._prefs.prayerAlertsFor};
                        on ? set.add(p.name) : set.remove(p.name);
                        await _prefs.setPrayerAlertsFor(set);
                        if (mounted) setState(() {});
                        await PrayerAlerts.instance.reschedule();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(t.prayerReminder, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, label: Text(t.reminderOff)),
                  for (final m in const [10, 15, 30]) ButtonSegment(value: m, label: Text(t.minutesShort(m))),
                ],
                selected: {_prefs.prayerReminderMinutes},
                onSelectionChanged: (s) async {
                  await _prefs.setPrayerReminderMinutes(s.first);
                  if (mounted) setState(() {});
                  await PrayerAlerts.instance.reschedule();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
