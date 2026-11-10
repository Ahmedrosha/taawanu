import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tour.dart';
import '../../widgets/tour_texts.dart';
import '../../widgets/ui.dart';
import 'adhkar_data.dart';
import 'hisn_screen.dart';
import 'tasbeeh_screen.dart';

String _dayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}

IconData _iconOf(String id) => switch (id) {
      'morning' => Icons.wb_sunny_outlined,
      'evening' => Icons.nights_stay_outlined,
      'afterPrayer' => Icons.mosque_outlined,
      'sleep' => Icons.bedtime_outlined,
      'waking' => Icons.wb_twilight_outlined,
      'quranDuas' => Icons.menu_book_outlined,
      _ => Icons.auto_stories_outlined,
    };

/// صفحة الأذكار: العناوين بس. فوق التسبيح وحصن المسلم والرقية الشرعية، وتحتهم أذكار اليوم والأدعية.
class AdhkarScreen extends StatefulWidget {
  const AdhkarScreen({super.key});

  @override
  State<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends State<AdhkarScreen> {
  late final Future<List<AdhkarCategory>> _data = AdhkarRepository.instance.daily();
  late final Future<List<HisnChapter>> _hisn = AdhkarRepository.instance.hisn();
  final _kTop = GlobalKey(), _kHisn = GlobalKey(), _kList = GlobalKey();

  static const _dailyIds = ['morning', 'evening', 'afterPrayer', 'sleep', 'waking'];

  @override
  void initState() {
    super.initState();
    Tour.schedule(context, 'adhkar', () => [
          TourStep(_kTop, tourText(context, 'adhkar.cats')),
          TourStep(_kHisn, tourText(context, 'adhkar.hisn'), radius: 20),
          TourStep(_kList, tourText(context, 'adhkar.item')),
        ]);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    // العدادات ممكن تكون اتغيرت.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    final counts = Prefs.instance.adhkarCounts(_dayKey());
    // الصباح لحد العصر تقريبًا، وبعدها المساء.
    final nowId = DateTime.now().hour < 15 ? 'morning' : 'evening';

    Widget big(IconData icon, String title, String sub, VoidCallback onTap, {Key? key}) => Expanded(
          child: Material(
            key: key,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: AppColors.border)),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
                child: Column(
                  children: [
                    CircleAvatar(radius: 24, backgroundColor: AppColors.goldTint, child: Icon(icon, color: AppColors.accent)),
                    const SizedBox(height: 10),
                    Text(title, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(sub, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget row(AdhkarCategory c, {bool now = false}) {
      final read = c.items.where((d) => (counts[d.id] ?? 0) >= d.count).length;
      final title = _dailyIds.contains(c.id) ? t.adhkarOf(en ? c.en : c.ar) : (en ? c.en : c.ar);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: now ? AppColors.accent : AppColors.border),
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: CircleAvatar(
              backgroundColor: AppColors.navy.withValues(alpha: 0.25),
              child: Icon(_iconOf(c.id), color: AppColors.accent, size: 20),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(read == 0 ? t.adhkarCount(c.items.length) : t.adhkarCountRead(c.items.length, read)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (now)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.goldTint, borderRadius: BorderRadius.circular(8)),
                    child: Text(t.adhkarNow, style: TextStyle(fontSize: 11, color: AppColors.goldText)),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _open(DhikrListScreen(title: title, sections: [c])),
          ),
        ),
      );
    }

    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
          child: Text(s, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(t.tabAdhkar, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: FutureBuilder<List<AdhkarCategory>>(
        future: _data,
        builder: (context, snap) {
          final cats = snap.data;
          if (cats == null) return const Center(child: CircularProgressIndicator());
          final daily = [for (final c in cats) if (_dailyIds.contains(c.id)) c]
            ..sort((a, b) => (a.id == nowId ? -1 : _dailyIds.indexOf(a.id)).compareTo(b.id == nowId ? -1 : _dailyIds.indexOf(b.id)));
          // "تسابيح" بقت جوه كارت التسبيح.
          final duas = [for (final c in cats) if (!_dailyIds.contains(c.id) && c.id != 'tasbeeh') c];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(
                key: _kTop,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  big(Icons.radio_button_checked, t.tasbeeh, t.tasbeehSub, () => _open(const TasbeehScreen())),
                  const SizedBox(width: 10),
                  FutureBuilder<List<HisnChapter>>(
                    future: _hisn,
                    builder: (context, h) => big(
                      Icons.menu_book_outlined,
                      t.hisnMuslim,
                      h.hasData ? t.hisnChapters(h.data!.length) : '',
                      () => _open(const HisnScreen()),
                      key: _kHisn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  big(Icons.shield_outlined, t.ruqyah, t.ruqyahSub, () => _open(const RuqyahScreen())),
                ],
              ),
              header(t.adhkarDaily),
              KeyedSubtree(key: _kList, child: row(daily.first, now: daily.first.id == nowId)),
              for (final c in daily.skip(1)) row(c),
              if (duas.isNotEmpty) header(t.adhkarDuas),
              for (final c in duas) row(c),
            ],
          );
        },
      ),
    );
  }
}

/// الرقية الشرعية: آيات من القرآن وأدعية من السنة.
class RuqyahScreen extends StatelessWidget {
  const RuqyahScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<List<AdhkarCategory>>(
      future: AdhkarRepository.instance.ruqyah(),
      builder: (context, snap) => snap.hasData
          ? DhikrListScreen(title: t.ruqyah, sections: snap.data!, note: t.ruqyahNote)
          : Scaffold(appBar: AppBar(title: Text(t.ruqyah)), body: const Center(child: CircularProgressIndicator())),
    );
  }
}

/// أذكار قسم (أو كذا قسم بعناوين): دوس على الذكر عشان العداد يزيد.
class DhikrListScreen extends StatefulWidget {
  const DhikrListScreen({super.key, required this.title, required this.sections, this.note});

  final String title;
  final List<AdhkarCategory> sections;
  final String? note;

  @override
  State<DhikrListScreen> createState() => _DhikrListScreenState();
}

class _DhikrListScreenState extends State<DhikrListScreen> {
  late final String _today = _dayKey();
  late final Map<String, int> _counts = Prefs.instance.adhkarCounts(_today);
  late final Future<QuranData> _quran = QuranRepository.instance.load();

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
      for (final s in widget.sections) {
        for (final d in s.items) {
          _counts.remove(d.id);
        }
      }
    });
    Prefs.instance.setAdhkarCounts(_today, _counts);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(tooltip: t.reset, onPressed: _reset, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<QuranData>(
        future: _quran,
        builder: (context, snap) {
          final q = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(widget.note!, style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6)),
                ),
              for (final s in widget.sections) ...[
                if (widget.sections.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                    child: Text(en ? s.en : s.ar, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  ),
                for (final d in s.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DhikrCard(dhikr: d, count: _counts[d.id] ?? 0, quran: q, onTap: () => _tap(d)),
                  ),
              ],
              Text(t.tapToCount, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          );
        },
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
