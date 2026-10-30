import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../widgets/ui.dart';

/// إعدادات المجموعة للأدمن والمساعد. الورد والنوع مبيتغيروش، وتغيير الدورة بيتطبق من الدورة الجاية.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({super.key, required this.group});

  final Group group;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final _name = TextEditingController(text: widget.group.name);
  late int _cycleCount = widget.group.cycleCount;
  late CycleUnit _unit = CycleUnit.values.byName(widget.group.cycleUnit);
  late int _startDay = widget.group.cycleStartDay;
  late int _startHour = widget.group.cycleStartHour;
  late int _startDayOfMonth = widget.group.cycleStartDayOfMonth;
  late LatePolicy _late = LatePolicy.values.byName(widget.group.lateDefault);
  late bool _open = widget.group.isOpen;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => GroupsService.instance.updateSettings(widget.group.id, {
        'name': _name.text.trim(),
        'cycleCount': _cycleCount,
        'cycleUnit': _unit.name,
        'cycleStartDay': _startDay,
        'cycleStartHour': _startHour,
        'cycleStartDayOfMonth': _startDayOfMonth,
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        'lateDefault': _late.name,
        'isOpen': _open,
      }),
      success: t.saved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(title: Text(t.groupSettings, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t.groupName, style: label),
          const SizedBox(height: 8),
          TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(counterText: '')),
          const SizedBox(height: 20),
          Text(t.cycleLabel, style: label),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(onPressed: _cycleCount > 1 ? () => setState(() => _cycleCount--) : null, icon: const Icon(Icons.remove)),
              SizedBox(width: 36, child: Text('$_cycleCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              IconButton.outlined(onPressed: _cycleCount < 30 ? () => setState(() => _cycleCount++) : null, icon: const Icon(Icons.add)),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<CycleUnit>(
                  showSelectedIcon: false,
                  segments: [for (final u in CycleUnit.values) ButtonSegment(value: u, label: Text(cycleUnitLabel(t, u)))],
                  selected: {_unit},
                  onSelectionChanged: (s) => setState(() => _unit = s.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(t.cycleChangeNote, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          if (_unit == CycleUnit.week) ...[
            Text(t.startDayLabel, style: label),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _startDay,
              items: [
                for (var d = 0; d < 7; d++)
                  DropdownMenuItem(value: d, child: Text(DateFormat.EEEE(locale).format(DateTime(2023, 1, 1 + d)))),
              ],
              onChanged: (v) => setState(() => _startDay = v ?? _startDay),
            ),
          ] else if (_unit == CycleUnit.day) ...[
            Text(t.startHourLabel, style: label),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _startHour,
              items: [
                for (var h = 0; h < 24; h++)
                  DropdownMenuItem(value: h, child: Text(MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: h, minute: 0)))),
              ],
              onChanged: (v) => setState(() => _startHour = v ?? _startHour),
            ),
          ] else ...[
            Text(t.startDayOfMonthLabel, style: label),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _startDayOfMonth,
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (v) => setState(() => _startDayOfMonth = v ?? _startDayOfMonth),
            ),
          ],
          const SizedBox(height: 20),
          Text(t.lateLabel, style: label),
          const SizedBox(height: 8),
          DropdownButtonFormField<LatePolicy>(
            initialValue: _late,
            items: [for (final p in LatePolicy.values) DropdownMenuItem(value: p, child: Text(latePolicyLabel(t, p)))],
            onChanged: (v) => setState(() => _late = v ?? _late),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.groupOpen),
            value: _open,
            onChanged: (v) => setState(() => _open = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(onPressed: _busy ? null : _save, child: Text(t.save)),
        ),
      ),
    );
  }
}
