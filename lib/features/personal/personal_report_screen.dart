import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/personal_ward.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import 'personal_ward_screen.dart' show personalItemTitle;

/// يوم في التقرير: المطلوب واللي اتعمل.
class _Day {
  const _Day(this.date, this.due, this.done);

  final DateTime date;
  final int due;
  final int done;

  bool get full => due > 0 && done >= due;
}

/// تقرير "أدائي" في الورد الشخصي: نسبة الإنجاز، والأيام الكاملة، والسلسلة، ولكل بند.
class PersonalReportScreen extends StatefulWidget {
  const PersonalReportScreen({super.key});

  @override
  State<PersonalReportScreen> createState() => _PersonalReportScreenState();
}

class _PersonalReportScreenState extends State<PersonalReportScreen> {
  final _ward = PersonalWard.instance;
  late final Future<QuranData> _quran = QuranRepository.instance.load();
  String _period = 'week'; // week | ten | thirty | month | lastMonth | custom
  DateTimeRange? _custom;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTimeRange get _range {
    final today = _day(DateTime.now());
    return switch (_period) {
      'ten' => DateTimeRange(start: today.subtract(const Duration(days: 9)), end: today),
      'thirty' => DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
      'month' => DateTimeRange(start: DateTime(today.year, today.month), end: today),
      'lastMonth' => DateTimeRange(start: DateTime(today.year, today.month - 1), end: DateTime(today.year, today.month, 0)),
      'custom' => _custom ?? DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      _ => DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
    };
  }

  /// المطلوب في يوم: المتسجّل، وإلا من البنود الحالية (حسب أيامها ويوم إضافتها).
  _Day _dayStats(DateTime d) {
    final key = personalDayKey(d);
    final current = [for (final i in _ward.items) if (i.dueOn(d) && !i.sinceDate.isAfter(d)) i];
    final due = _ward.dueOn(key) ?? current.length;
    final ids = _ward.doneOn(key).toSet();
    final done = ids.length > due ? due : ids.length;
    return _Day(d, due, done);
  }

  List<_Day> _days(DateTimeRange r) {
    final today = _day(DateTime.now());
    final out = <_Day>[];
    for (var d = _day(r.start); !d.isAfter(r.end) && !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(_dayStats(d));
    }
    return out;
  }

  /// السلسلة الحالية: أيام كاملة ورا بعض لحد النهارده (النهارده مبيقطعهاش لو لسه مخلصش).
  int _currentStreak() {
    final today = _day(DateTime.now());
    var n = 0;
    for (var i = 0; i < 400; i++) {
      final d = today.subtract(Duration(days: i));
      final s = _dayStats(d);
      if (s.due == 0) {
        if (_ward.items.every((it) => it.sinceDate.isAfter(d))) break;
        continue; // يوم مفيهوش حاجة مطلوبة: مبيقطعش.
      }
      if (s.full) {
        n++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }
    return n;
  }

  int _longestStreak(List<_Day> days) {
    var best = 0, cur = 0;
    for (final d in days) {
      if (d.due == 0) continue;
      cur = d.full ? cur + 1 : 0;
      if (cur > best) best = cur;
    }
    return best;
  }

  Future<void> _pickCustom() async {
    final today = _day(DateTime.now());
    final r = await showDateRangePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 400)),
      lastDate: today,
      initialDateRange: _custom ?? _range,
    );
    if (r != null) {
      setState(() {
        _custom = r;
        _period = 'custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final en = locale == 'en';
    final range = _range;
    final days = _days(range);
    final active = [for (final d in days) if (d.due > 0) d];
    final due = active.fold<int>(0, (a, d) => a + d.due);
    final done = active.fold<int>(0, (a, d) => a + d.done);
    final pct = due == 0 ? 0 : (done * 100 / due).round();
    final full = active.where((d) => d.full).length;
    final fmt = DateFormat.MMMd(locale);
    return Scaffold(
      appBar: AppBar(title: Text(t.personalReport, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: FutureBuilder<QuranData>(
        future: _quran,
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (k, label) in [
                  ('week', t.reportLastWeek),
                  ('ten', t.reportLast10),
                  ('thirty', t.reportLast30),
                  ('month', t.reportThisMonth),
                  ('lastMonth', t.reportLastMonth),
                ])
                  ChoiceChip(label: Text(label), selected: _period == k, onSelected: (_) => setState(() => _period = k)),
                ChoiceChip(
                  label: Text(_period == 'custom' ? '${fmt.format(range.start)} – ${fmt.format(range.end)}' : t.reportCustom),
                  selected: _period == 'custom',
                  onSelected: (_) => _pickCustom(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (active.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(t.reportEmpty, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, height: 1.7)),
              )
            else ...[
              Row(
                children: [
                  Expanded(child: _Stat(value: '$pct%', label: t.reportCompletion, color: AppColors.statusDone)),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(value: '$full / ${active.length}', label: t.reportFullDays)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _Stat(value: '${_currentStreak()}', label: t.reportStreak)),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(value: '${_longestStreak(days)}', label: t.reportBestStreak)),
                ],
              ),
              const SizedBox(height: 14),
              AppCard(child: _Bars(days: days, locale: locale)),
              const SizedBox(height: 16),
              Text(t.reportPerItem, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              for (final i in _ward.items)
                Builder(builder: (context) {
                  var need = 0, got = 0;
                  for (final d in days) {
                    if (!i.dueOn(d.date) || i.sinceDate.isAfter(d.date)) continue;
                    need++;
                    if (_ward.doneOn(personalDayKey(d.date)).contains(i.id)) got++;
                  }
                  if (need == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(personalItemTitle(t, i, snap.data, _ward.adhkarCategories, en), style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(t.personalProgress(got, need), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ProgressLine(value: got / need),
                      ],
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color ?? AppColors.text)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );
}

/// أعمدة الإنجاز: عمود لكل يوم (وأكتر من ٦٢ يوم: عمود لكل أسبوع).
class _Bars extends StatelessWidget {
  const _Bars({required this.days, required this.locale});

  final List<_Day> days;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final weekly = days.length > 62;
    final groups = <(DateTime, int, int)>[];
    if (weekly) {
      for (var i = 0; i < days.length; i += 7) {
        final chunk = days.sublist(i, (i + 7).clamp(0, days.length));
        groups.add((chunk.first.date, chunk.fold(0, (a, d) => a + d.due), chunk.fold(0, (a, d) => a + d.done)));
      }
    } else {
      groups.addAll([for (final d in days) (d.date, d.due, d.done)]);
    }
    final labelEvery = (groups.length / 7).ceil().clamp(1, 1000);
    final fmt = weekly || groups.length > 10 ? DateFormat.Md(locale) : DateFormat.E(locale);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (k, g) in groups.indexed)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: groups.length > 31 ? 0.5 : 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: g.$2 == 0 ? 0.03 : (g.$3 / g.$2).clamp(0.03, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: g.$2 == 0 ? AppColors.track : (g.$3 >= g.$2 ? AppColors.statusDone : AppColors.statusInProgress),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14,
                      child: k % labelEvery == 0
                          ? FittedBox(child: Text(fmt.format(g.$1), style: TextStyle(fontSize: 10, color: AppColors.textMuted)))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
