import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../services/tafsir_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/quran_style.dart';

/// ورقة التفسير: الآية بخط المصحف وتحتها تفسيرها، مع التنقل للآية اللي قبلها وبعدها.
Future<void> showTafsirSheet(BuildContext context, {required int surah, required int ayah, void Function(int surah, int ayah)? onPlay}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scroll) => _TafsirBody(surah: surah, ayah: ayah, scroll: scroll, onPlay: onPlay),
    ),
  );
}

class _TafsirBody extends StatefulWidget {
  const _TafsirBody({required this.surah, required this.ayah, required this.scroll, this.onPlay});

  /// تشغيل التلاوة من الآية دي.
  final void Function(int surah, int ayah)? onPlay;

  final int surah;
  final int ayah;
  final ScrollController scroll;

  @override
  State<_TafsirBody> createState() => _TafsirBodyState();
}

class _TafsirBodyState extends State<_TafsirBody> {
  late int _surah = widget.surah;
  late int _ayah = widget.ayah;
  late String _tafsir = Prefs.instance.tafsirId;
  int _retry = 0;
  final _quran = QuranRepository.instance.loadMadinah();

  void _go(QuranData q, int delta) {
    var s = _surah, a = _ayah + delta;
    if (a < 1) {
      if (s == 1) return;
      s--;
      a = q.ayahCount(s);
    } else if (a > q.ayahCount(s)) {
      if (s == 114) return;
      s++;
      a = 1;
    }
    setState(() {
      _surah = s;
      _ayah = a;
    });
    if (widget.scroll.hasClients) widget.scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ar = Localizations.localeOf(context).languageCode != 'en';
    final info = TafsirRepository.info(_tafsir);
    return FutureBuilder<QuranData>(
      future: _quran,
      builder: (context, qSnap) {
        final q = qSnap.data;
        if (q == null) return const Center(child: CircularProgressIndicator());
        final name = q.surahName(_surah, ar ? 'ar' : 'en').replaceFirst(RegExp(r'^سُوْرَةُ\s*'), '');
        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: t.previousAyah,
                  onPressed: () => _go(q, -1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    t.ayahRef(name, _ayah),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton(
                  tooltip: t.nextAyah,
                  onPressed: () => _go(q, 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (widget.onPlay != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onPlay!(_surah, _ayah);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t.listenFromHere),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
              child: Text(
                q.ayahText(_surah, _ayah),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: quranTextStyle(madinahFont, fontSize: 22, color: AppColors.text),
              ),
            ),
            const SizedBox(height: 14),
            // اختيار التفسير.
            Wrap(
              spacing: 8,
              children: [
                for (final x in TafsirRepository.tafsirs)
                  ChoiceChip(
                    label: Text(ar ? x.nameAr : x.nameEn),
                    selected: x.id == _tafsir,
                    showCheckmark: false,
                    selectedColor: AppColors.navy,
                    labelStyle: TextStyle(color: x.id == _tafsir ? Colors.white : AppColors.text),
                    onSelected: (_) {
                      setState(() => _tafsir = x.id);
                      Prefs.instance.setTafsirId(x.id);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<TafsirEntry?>(
              key: ValueKey('$_tafsir:$_surah:$_ayah:$_retry'),
              future: TafsirRepository.instance.ayah(_tafsir, _surah, _ayah),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Column(
                    children: [
                      const SizedBox(height: 12),
                      Icon(Icons.wifi_off, color: AppColors.textMuted),
                      const SizedBox(height: 8),
                      Text(t.tafsirOffline, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                      TextButton(onPressed: () => setState(() => _retry++), child: Text(t.retry)),
                    ],
                  );
                }
                final e = snap.data;
                if (e == null) return Text(t.tafsirUnavailable, style: TextStyle(color: AppColors.textMuted));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (e.isGroup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(t.tafsirGroup(e.fromAyah, e.toAyah), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ),
                    SelectableText.rich(
                      tafsirSpans(e.text, fontSize: 16),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(ar ? info.sourceAr : info.sourceEn, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        );
      },
    );
  }
}

/// النص بعلامات `<q>` (قرآن) `<b>` (عنوان) `<r>` (تنبيه) `<h>` (فاصل) => نص منسّق.
TextSpan tafsirSpans(String text, {required double fontSize}) {
  final base = TextStyle(fontSize: fontSize, height: 1.9, color: AppColors.text);
  final spans = <InlineSpan>[];
  final re = RegExp(r'<(q|b|r|h)>(.*?)</\1>', dotAll: true);
  var i = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
    final inner = m.group(2)!;
    switch (m.group(1)) {
      case 'q':
        spans.add(TextSpan(text: inner, style: TextStyle(fontFamily: madinahFont, color: AppColors.accent, fontSize: fontSize * 1.05)));
      case 'b':
        spans.add(TextSpan(text: inner, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)));
      case 'r':
        spans.add(TextSpan(text: inner, style: TextStyle(color: AppColors.statusLate)));
      default:
        spans.add(TextSpan(text: inner, style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)));
    }
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return TextSpan(style: base, children: spans);
}
