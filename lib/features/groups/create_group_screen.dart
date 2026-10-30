import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../theme/app_colors.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  bool _isPrivate = true;
  int _ward = 8; // جزء
  int _cycleCount = 1;
  CycleUnit _unit = CycleUnit.week;
  int _startDay = 5; // الجمعة (٠ = الأحد)
  int _startHour = 6;
  int _startDayOfMonth = 1;
  LatePolicy _late = LatePolicy.ask;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await GroupsService.instance.createGroup(
        name: _name.text.trim(),
        isPrivate: _isPrivate,
        wardQuarters: _ward,
        cycleCount: _cycleCount,
        cycleUnit: _unit,
        cycleStartDay: _startDay,
        cycleStartHour: _startHour,
        cycleStartDayOfMonth: _startDayOfMonth,
        lateDefault: _late,
      );
      messenger.showSnackBar(SnackBar(content: Text(t.groupCreated)));
      if (mounted) context.pop();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('createGroup failed: ${e.code} ${e.message}');
      messenger.showSnackBar(SnackBar(content: Text(t.createFailed)));
    } catch (e) {
      debugPrint('createGroup failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(t.createFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// اسم يوم الأسبوع باللغة الحالية. ٠ = الأحد.
  String _dayName(BuildContext context, int day) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    // ١ يناير ٢٠٢٣ كان يوم أحد.
    return DateFormat.EEEE(locale).format(DateTime(2023, 1, 1 + day));
  }

  String _hourLabel(BuildContext context, int hour) {
    return MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: hour, minute: 0));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final label = text.titleSmall?.copyWith(fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(title: Text(t.newGroup, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(t.groupName, style: label),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: t.groupNameHint, counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? t.nameRequired : null,
            ),
            const SizedBox(height: 20),

            Text(t.groupType, style: label),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: true, label: Text(t.groupTypePrivate), icon: const Icon(Icons.lock_outline)),
                ButtonSegment(value: false, label: Text(t.groupTypePublic), icon: const Icon(Icons.public)),
              ],
              selected: {_isPrivate},
              onSelectionChanged: (s) => setState(() => _isPrivate = s.first),
            ),
            const SizedBox(height: 20),

            Text(t.wardLabel, style: label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in wardOptions)
                  ChoiceChip(
                    label: Text(wardLabel(t, w)),
                    selected: _ward == w,
                    showCheckmark: false,
                    selectedColor: AppColors.navy,
                    labelStyle: TextStyle(color: _ward == w ? Colors.white : AppColors.text),
                    onSelected: (_) => setState(() => _ward = w),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.slotsInfo(totalQuarters ~/ _ward),
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),

            Text(t.cycleLabel, style: label),
            const SizedBox(height: 8),
            Row(
              children: [
                _Stepper(
                  value: _cycleCount,
                  onChanged: (v) => setState(() => _cycleCount = v),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<CycleUnit>(
                    showSelectedIcon: false,
                    segments: [
                      for (final u in CycleUnit.values)
                        ButtonSegment(value: u, label: Text(cycleUnitLabel(t, u))),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (s) => setState(() => _unit = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // بداية الدورة بتختلف حسب الوحدة.
            if (_unit == CycleUnit.week) ...[
              Text(t.startDayLabel, style: label),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _startDay,
                items: [
                  for (var d = 0; d < 7; d++)
                    DropdownMenuItem(value: d, child: Text(_dayName(context, d))),
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
                    DropdownMenuItem(value: h, child: Text(_hourLabel(context, h))),
                ],
                onChanged: (v) => setState(() => _startHour = v ?? _startHour),
              ),
            ] else ...[
              Text(t.startDayOfMonthLabel, style: label),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _startDayOfMonth,
                items: [
                  for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) => setState(() => _startDayOfMonth = v ?? _startDayOfMonth),
              ),
            ],
            const SizedBox(height: 20),

            Text(t.lateLabel, style: label),
            const SizedBox(height: 8),
            DropdownButtonFormField<LatePolicy>(
              initialValue: _late,
              items: [
                for (final p in LatePolicy.values)
                  DropdownMenuItem(value: p, child: Text(latePolicyLabel(t, p))),
              ],
              onChanged: (v) => setState(() => _late = v ?? _late),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(t.createGroup),
          ),
        ),
      ),
    );
  }
}

/// عداد من ١ لـ٣٠ لمدة الدورة.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '-',
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: '+',
            onPressed: value < 30 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
