import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/quran_repository.dart';
import '../../services/tafsir_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/quran_style.dart';

/// ورقة التفسير: الآية بخط المصحف وتحتها تفسيرها، مع التنقل للآية اللي قبلها وبعدها.
Future<void> showTafsirSheet(BuildContext context, {required int surah, required int ayah}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scroll) => _TafsirBody(surah: surah, ayah: ayah, scroll: scroll),
    ),
  );
}

class _TafsirBody extends StatefulWidget {
  const _TafsirBody({required this.surah, required this.ayah, required this.scroll});

  final int surah;
  final int ayah;
  final ScrollController scroll;

  @override
  State<_TafsirBody> createState() => _TafsirBodyState();
}

class _TafsirBodyState extends State<_TafsirBody> {
  late int _surah = widget.surah;
  late int _ayah = widget.ayah;
  final String _tafsir = TafsirRepository.tafsirs.first.id;
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
    final info = TafsirRepository.tafsirs.firstWhere((x) => x.id == _tafsir);
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
            Text(ar ? info.nameAr : info.nameEn, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
            const SizedBox(height: 6),
            FutureBuilder<String?>(
              key: ValueKey('$_tafsir:$_surah:$_ayah'),
              future: TafsirRepository.instance.ayah(_tafsir, _surah, _ayah),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                }
                return SelectableText(
                  snap.data ?? t.tafsirUnavailable,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 16, height: 1.9, color: AppColors.text),
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
