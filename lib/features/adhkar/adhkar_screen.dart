import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import 'adhkar_data.dart';
import 'hisn_screen.dart';

class AdhkarScreen extends StatefulWidget {
  const AdhkarScreen({super.key});

  @override
  State<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends State<AdhkarScreen> {
  String _cat = _defaultCategory();
  late final String _today = _dayKey();
  late final Map<String, int> _counts = Prefs.instance.adhkarCounts(_today);
  late final Future<List<AdhkarCategory>> _data = AdhkarRepository.instance.daily();

  static String _dayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// الصباح لحد العصر تقريبًا، وبعدها المساء.
  static String _defaultCategory() => DateTime.now().hour < 15 ? 'morning' : 'evening';

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

  void _reset(AdhkarCategory cat) {
    setState(() {
      for (final d in cat.items) {
        _counts.remove(d.id);
      }
    });
    Prefs.instance.setAdhkarCounts(_today, _counts);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    return FutureBuilder<List<AdhkarCategory>>(
      future: _data,
      builder: (context, dSnap) {
        final cats = dSnap.data;
        final cat = cats?.firstWhere((c) => c.id == _cat, orElse: () => cats.first);
        return Scaffold(
          appBar: AppBar(
            title: Text(t.tabAdhkar, style: const TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              if (cat != null) IconButton(tooltip: t.reset, onPressed: () => _reset(cat), icon: const Icon(Icons.refresh)),
            ],
          ),
          body: cats == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // الأقسام، وآخرها حصن المسلم كله.
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final c in cats)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                label: Text(en ? c.en : c.ar),
                                selected: c.id == cat!.id,
                                showCheckmark: false,
                                selectedColor: AppColors.navy,
                                labelStyle: TextStyle(color: c.id == cat.id ? Colors.white : AppColors.text),
                                onSelected: (_) => setState(() => _cat = c.id),
                              ),
                            ),
                          ActionChip(
                            avatar: Icon(Icons.menu_book_outlined, size: 18, color: AppColors.accent),
                            label: Text(t.hisnMuslim),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HisnScreen())),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: FutureBuilder<QuranData>(
                        future: QuranRepository.instance.load(),
                        builder: (context, snap) {
                          final q = snap.data;
                          final items = cat!.items;
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: items.length + 1,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              if (i == items.length) {
                                return Text(t.tapToCount, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted));
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
      },
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
      color: done ? AppColors.doneTint : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: done ? AppColors.doneBorder : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text ?? '…',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.justify,
                style: isQuran
                    ? GoogleFonts.getFont('Amiri Quran', fontSize: 20, height: 2.0, color: AppColors.text)
                    : GoogleFonts.amiri(fontSize: 19, height: 1.9, color: AppColors.text),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: ProgressLine(value: count / dhikr.count)),
                  const SizedBox(width: 12),
                  Text(
                    done ? t.doneCheck : '$count / ${dhikr.count}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: done ? AppColors.statusDone : AppColors.accent),
                  ),
                ],
              ),
              if (dhikr.virtue != null) ...[
                const SizedBox(height: 8),
                Text(dhikr.virtue!, textDirection: TextDirection.rtl, style: TextStyle(fontSize: 13, color: AppColors.goldText, height: 1.6)),
              ],
              if (dhikr.source != null) ...[
                const SizedBox(height: 4),
                Text(dhikr.source!, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
