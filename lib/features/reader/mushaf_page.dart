import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/mushaf_fonts.dart';
import '../../services/mushaf_layout.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';

/// صفحة من مصحف المدينة: نفس السطور ونفس الكلمات في كل سطر زي المطبوع.
/// [qpc] = خط صفحات المجمع (مطابق للمطبوع)، وإلا خط حفص اللي جوه التطبيق.
/// [inRange]: الآيات اللي برا الورد بتظهر باهتة.
class MushafPage extends StatelessWidget {
  const MushafPage({
    super.key,
    required this.layout,
    required this.quran,
    required this.page,
    required this.qpc,
    this.inRange,
    this.onUseHafs,
  });

  final MushafLayout layout;
  final QuranData quran;
  final int page;
  final bool qpc;
  final bool Function(int surah, int ayah)? inRange;

  /// لو خطوط المجمع مش قادرة تتحمّل: زرار يرجّع لخط حفص.
  final VoidCallback? onUseHafs;

  @override
  Widget build(BuildContext context) {
    if (!qpc) return _PageBody(page: page, qpc: false, layout: layout, quran: quran, inRange: inRange);
    final fonts = MushafFonts.instance;
    return ListenableBuilder(
      listenable: fonts,
      builder: (context, _) => fonts.isReady(page)
          ? _PageBody(page: page, qpc: true, layout: layout, quran: quran, inRange: inRange)
          : _FontLoader(page: page, onUseHafs: onUseHafs),
    );
  }
}

/// بيحمّل خط الصفحة، ولو مفيش نت بيقول كده مع زرار إعادة المحاولة.
class _FontLoader extends StatefulWidget {
  const _FontLoader({required this.page, this.onUseHafs});

  final int page;
  final VoidCallback? onUseHafs;

  @override
  State<_FontLoader> createState() => _FontLoaderState();
}

class _FontLoaderState extends State<_FontLoader> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final ok = await MushafFonts.instance.ensurePage(widget.page);
    if (!ok && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_failed) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: AppColors.textMuted, size: 36),
            const SizedBox(height: 12),
            Text(t.mushafFontOffline, textAlign: TextAlign.center, style: TextStyle(color: AppColors.text)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(t.retry)),
            if (widget.onUseHafs != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: widget.onUseHafs, child: Text(t.useHafsPages)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.qpc, required this.layout, required this.quran, this.inRange});

  final int page;
  final bool qpc;
  final MushafLayout layout;
  final QuranData quran;
  final bool Function(int surah, int ayah)? inRange;

  static const _slots = 15;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ar = Localizations.localeOf(context).languageCode != 'en';
    final lines = layout.page(page);
    final (s0, a0) = layout.firstAyahOf(page);
    final juz = (quran.quarterOf(s0, a0) - 1) ~/ 8 + 1;
    final surahNames = layout
        .surahsOn(page)
        .map((s) => ar ? quran.surahNamesAr[s - 1].replaceFirst(RegExp(r'^سُوْرَةُ\s*'), '') : quran.surahNamesEn[s - 1])
        .join(ar ? '، ' : ', ');
    final labelStyle = TextStyle(fontSize: 12, color: AppColors.paperLabel, fontWeight: FontWeight.w600);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: Column(
          children: [
            // أعلى الصفحة: اسم السورة يمين، ورقم الجزء شمال، زي المصحف.
            SizedBox(
              height: 22,
              child: Row(
                children: [
                  Expanded(child: Text(surahNames, style: labelStyle, overflow: TextOverflow.ellipsis)),
                  Text(t.juzLabel(juz), style: labelStyle),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.paperLine, width: 1.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: LayoutBuilder(
                  builder: (context, c) => _lines(context, lines, c.maxWidth, c.maxHeight),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: Center(child: Text(_number(page, ar), style: labelStyle.copyWith(fontSize: 13))),
            ),
          ],
        ),
      ),
    );
  }

  String _number(int n, bool ar) {
    if (!ar) return '$n';
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  String _word(MushafWord w) => qpc ? w.qpc : w.hafs;

  String get _family => qpc ? MushafFonts.familyFor(page) : madinahFont;

  Widget _lines(BuildContext context, List<MushafLine> lines, double width, double height) {
    final lineH = height / _slots;
    final m = _PageMetrics.of(page: page, qpc: qpc, family: _family, width: width, lineH: lineH, lines: lines, word: _word);
    final ink = AppColors.text;
    final dim = AppColors.textMuted.withValues(alpha: 0.3);
    final style = TextStyle(fontFamily: _family, fontSize: m.fontSize, height: 1.0, color: ink);
    // صفحة ١ و٢ في المصحف سطورها في النص.
    final allCentered = page <= 2;

    final children = <Widget>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      Widget child;
      switch (l.type) {
        case MushafLineType.surahHeader:
          child = _SurahHeader(name: quran.surahNamesAr[l.surah - 1], height: lineH);
        case MushafLineType.basmala:
          child = Center(
            child: Text(
              qpc ? MushafFonts.basmalaGlyphs : quran.basmala,
              textDirection: TextDirection.rtl,
              softWrap: false,
              style: qpc ? style.copyWith(fontFamily: MushafFonts.basmalaFamily) : style,
            ),
          );
        case MushafLineType.text:
          final words = [
            for (final w in l.words)
              if (_word(w).isNotEmpty)
                Text(
                  _word(w),
                  softWrap: false,
                  textDirection: TextDirection.rtl,
                  style: inRange == null || inRange!(w.surah, w.ayah) ? style : style.copyWith(color: dim),
                ),
          ];
          final centered = allCentered || m.natural[i] < m.maxNatural * 0.75;
          child = centered
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < words.length; k++) ...[
                      if (k > 0) SizedBox(width: m.fontSize * 0.28),
                      words[k],
                    ],
                  ],
                )
              : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: words);
      }
      children.add(SizedBox(height: lineH, child: Center(child: child)));
    }
    return Column(
      mainAxisAlignment: lines.length < _slots ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: children,
    );
  }
}

/// حجم الخط المناسب للصفحة: أطول سطر ياخد عرض الصفحة. بيتحسب مرة لكل صفحة ومقاس.
class _PageMetrics {
  _PageMetrics(this.fontSize, this.natural, this.maxNatural);

  final double fontSize;

  /// عرض كل سطر بحجم الخط ده من غير فراغات زيادة (٠ لغير سطور النص).
  final List<double> natural;
  final double maxNatural;

  static final _cache = <String, _PageMetrics>{};

  static _PageMetrics of({
    required int page,
    required bool qpc,
    required String family,
    required double width,
    required double lineH,
    required List<MushafLine> lines,
    required String Function(MushafWord) word,
  }) {
    final key = '$page|$qpc|${width.round()}|${lineH.round()}';
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 60) _cache.clear();

    const ref = 40.0;
    final widths = <double>[];
    for (final l in lines) {
      if (l.type != MushafLineType.text) {
        widths.add(0);
        continue;
      }
      final text = l.words.map(word).where((w) => w.isNotEmpty).join(' ');
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontFamily: family, fontSize: ref, height: 1.0)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      widths.add(tp.width);
      tp.dispose();
    }
    final maxRef = widths.fold<double>(0, (a, b) => b > a ? b : a);
    // أطول سطر = ٩٧٪ من العرض، ومن غير ما الخط يكبر عن ارتفاع السطر.
    var size = maxRef > 0 ? ref * width * 0.97 / maxRef : lineH * 0.5;
    final cap = lineH * (qpc ? 0.62 : 0.5);
    if (size > cap) size = cap;
    final scale = size / ref;
    return _cache[key] = _PageMetrics(size, [for (final w in widths) w * scale], maxRef * scale);
  }
}

/// إطار اسم السورة.
class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.name, required this.height});

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FramePainter(line: AppColors.goldInk, fill: AppColors.goldTint),
      child: SizedBox(
        height: height * 0.86,
        width: double.infinity,
        child: Center(
          child: Text(
            name,
            textDirection: TextDirection.rtl,
            softWrap: false,
            style: TextStyle(fontFamily: madinahFont, fontSize: height * 0.4, height: 1.0, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.line, required this.fill});

  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(outer, Paint()..color = fill);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(outer, stroke);
    canvas.drawRRect(outer.deflate(3.5), stroke..strokeWidth = 0.8);
    // زخرفة صغيرة على الجنبين.
    final dot = Paint()..color = line;
    final r = size.height * 0.12;
    for (final x in [size.height * 0.55, size.width - size.height * 0.55]) {
      final c = Offset(x, size.height / 2);
      canvas.drawCircle(c, r, dot);
      canvas.drawCircle(c, r * 1.9, Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.line != line || old.fill != fill;
}
