import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import 'adhkar_data.dart';

class AdhkarScreen extends StatefulWidget {
  const AdhkarScreen({super.key});

  @override
  State<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends State<AdhkarScreen> {
  AdhkarCategory _cat = _defaultCategory();
  late final String _today = _dayKey();
  late final Map<String, int> _counts = Prefs.instance.adhkarCounts(_today);

  static String _dayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// الصباح لحد العصر تقريبًا، وبعدها المساء.
  static AdhkarCategory _defaultCategory() => DateTime.now().hour < 15 ? AdhkarCategory.morning : AdhkarCategory.evening;

  String _label(AppLocalizations t, AdhkarCategory c) => switch (c) {
        AdhkarCategory.morning => t.adhkarMorning,
        AdhkarCategory.evening => t.adhkarEvening,
        AdhkarCategory.afterPrayer => t.adhkarAfterPrayer,
        AdhkarCategory.sleep => t.adhkarSleep,
      };

  void _tap(Dhikr d) {
    final c = _counts[d.id] ?? 0;
    if (c >= d.count) return;
    setState(() => _counts[d.id] = c + 1);
    if (c + 1 == d.count) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    Prefs.instance.setAdhkarCounts(_today, _counts);
  }

  void _reset() {
    setState(() {
      for (final d in adhkar[_cat]!) {
        _counts.remove(d.id);
      }
    });
    Prefs.instance.setAdhkarCounts(_today, _counts);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = adhkar[_cat]!;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabAdhkar, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(tooltip: t.reset, onPressed: _reset, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<AdhkarCategory>(
              showSelectedIcon: false,
              segments: [
                for (final c in AdhkarCategory.values)
                  ButtonSegment(value: c, label: Text(_label(t, c), style: const TextStyle(fontSize: 12))),
              ],
              selected: {_cat},
              onSelectionChanged: (s) => setState(() => _cat = s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<QuranData>(
              future: QuranRepository.instance.load(),
              builder: (context, snap) {
                final q = snap.data;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: items.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return Text(t.tapToCount, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textMuted));
                    }
                    final d = items[i];
                    return _DhikrCard(dhikr: d, count: _counts[d.id] ?? 0, quran: q, onTap: () => _tap(d));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DhikrCard extends StatelessWidget {
  const _DhikrCard({required this.dhikr, required this.count, required this.quran, required this.onTap});

  final Dhikr dhikr;
  final int count;
  final QuranData? quran;
  final VoidCallback onTap;

  String? _text() {
    if (dhikr.text != null) return dhikr.text;
    final ref = dhikr.quran;
    final q = quran;
    if (ref == null || q == null) return null;
    final (s, from, to) = ref;
    // الآيات من نص المصحف المدمج، من غير تعديل.
    return [for (var a = from; a <= to; a++) q.ayahText(s, a)].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final done = count >= dhikr.count;
    final text = _text();
    final isQuran = dhikr.quran != null;
    return Material(
      color: done ? const Color(0xFFF0FDF4) : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: done ? const Color(0xFF86EFAC) : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text ?? '…',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.justify,
                style: isQuran
                    ? GoogleFonts.getFont('Amiri Quran', fontSize: 20, height: 2.0)
                    : GoogleFonts.amiri(fontSize: 19, height: 1.9),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: ProgressLine(value: count / dhikr.count)),
                  const SizedBox(width: 12),
                  Text(
                    done ? t.doneCheck : '$count / ${dhikr.count}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: done ? AppColors.statusDone : AppColors.navy),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(dhikr.source, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
