import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/groups_service.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../groups/group_board_screen.dart' show ReadRequest;

const _paper = Color(0xFFFFFDF7);
const _paperLine = Color(0xFFECE6D6);

/// قراءة الورد ربع ربع، وتسجيل كل ربع لما يخلص.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.request});

  final ReadRequest request;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _read = widget.request.quartersRead;
  late double _fontSize = Prefs.instance.readerFontSize;
  bool _busy = false;
  final _keys = <int, GlobalKey>{};
  bool _scrolled = false;

  ReadRequest get r => widget.request;

  GlobalKey _keyFor(int q) => _keys.putIfAbsent(q, GlobalKey.new);

  void _scrollToCurrent() {
    if (_scrolled || _read == 0 || _read >= r.quarterCount) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(r.fromQuarter + _read).currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
    });
  }

  Future<void> _markQuarter() async {
    final t = AppLocalizations.of(context);
    final svc = GroupsService.instance;
    final next = _read + 1;
    final finishing = r.isPortion || next == r.quarterCount;
    setState(() => _busy = true);
    var points = 0;
    final ok = await runAction(context, () async {
      if (r.isPortion) {
        points = await svc.completePortion(r.groupId, r.portionId!);
      } else {
        points = await svc.updateProgress(r.groupId, next);
      }
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _read = r.isPortion ? r.quarterCount : next;
    });
    if (ok && finishing) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.earnedPoints(points))));
      context.pop();
    }
  }

  Future<void> _changeFont(double delta) async {
    final v = (_fontSize + delta).clamp(18.0, 40.0);
    setState(() => _fontSize = v);
    await Prefs.instance.setReaderFontSize(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rangeLabel(t, r.fromQuarter, r.toQuarter), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(r.groupName, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          IconButton(tooltip: t.textSize, onPressed: () => _changeFont(-2), icon: const Icon(Icons.text_decrease)),
          IconButton(tooltip: t.textSize, onPressed: () => _changeFont(2), icon: const Icon(Icons.text_increase)),
        ],
      ),
      body: FutureBuilder<QuranData>(
        future: QuranRepository.instance.load(),
        builder: (context, snap) {
          final q = snap.data;
          if (q == null) return const Center(child: CircularProgressIndicator());
          _scrollToCurrent();
          return CustomScrollView(
            slivers: [
              for (var i = 0; i < r.quarterCount; i++) ...[
                SliverToBoxAdapter(
                  child: _QuarterHeader(
                    key: _keyFor(r.fromQuarter + i),
                    label: rangeLabel(t, r.fromQuarter + i, r.fromQuarter + i),
                    done: i < _read,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverToBoxAdapter(child: _QuarterText(data: q, quarter: r.fromQuarter + i, fontSize: _fontSize)),
                ),
                if (!r.isPortion && i == _read)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: FilledButton(
                        onPressed: _busy ? null : _markQuarter,
                        child: Text(i == r.quarterCount - 1 ? t.finishedPortion : t.markQuarterDone),
                      ),
                    ),
                  ),
              ],
              if (r.isPortion)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: FilledButton(onPressed: _busy ? null : _markQuarter, child: Text(t.finishPortionExtra)),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
      bottomNavigationBar: r.isPortion
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressLine(value: _read / r.quarterCount),
                    const SizedBox(height: 6),
                    Text(t.quartersProgress(_read, r.quarterCount), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
    );
  }
}

class _QuarterHeader extends StatelessWidget {
  const _QuarterHeader({super.key, required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Row(
        children: [
          const Expanded(child: Divider(color: _paperLine)),
          const SizedBox(width: 10),
          if (done) const Icon(Icons.check_circle, size: 18, color: AppColors.statusDone),
          if (done) const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Color(0xFF8A7A4E), fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: _paperLine)),
        ],
      ),
    );
  }
}

/// نص الربع: عنوان السورة والبسملة عند بداية كل سورة، وأرقام الآيات.
class _QuarterText extends StatelessWidget {
  const _QuarterText({required this.data, required this.quarter, required this.fontSize});

  final QuranData data;
  final int quarter;
  final double fontSize;

  static const _digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  String _arabicNumber(int n) => n.toString().split('').map((d) => _digits[int.parse(d)]).join();

  @override
  Widget build(BuildContext context) {
    final ayahs = data.ayahsOfQuarter(quarter);
    final quranStyle = GoogleFonts.getFont('Amiri Quran', fontSize: fontSize, height: 2.1, color: AppColors.text);
    final markStyle = quranStyle.copyWith(fontSize: fontSize * 0.8, color: const Color(0xFF8A6A14));

    // نقسم الآيات لمجموعات حسب السورة، عشان نحط عنوان السورة قبل أول آية فيها.
    final blocks = <Widget>[];
    var spans = <InlineSpan>[];
    void flush() {
      if (spans.isEmpty) return;
      blocks.add(Text.rich(TextSpan(children: spans), textAlign: TextAlign.justify, textDirection: TextDirection.rtl));
      spans = [];
    }

    for (final a in ayahs) {
      if (a.number == 1) {
        flush();
        blocks.add(_SurahTitle(name: data.surahNamesAr[a.surah - 1], fontSize: fontSize));
        if (a.surah != 1 && a.surah != 9) {
          blocks.add(Text(data.basmala, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: quranStyle));
        }
      }
      spans.add(TextSpan(text: '${a.text} ', style: quranStyle));
      spans.add(TextSpan(text: '﴿${_arabicNumber(a.number)}﴾ ', style: markStyle));
    }
    flush();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks),
    );
  }
}

class _SurahTitle extends StatelessWidget {
  const _SurahTitle({required this.name, required this.fontSize});

  final String name;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.sky,
        border: Border.all(color: AppColors.navy, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: GoogleFonts.amiri(fontSize: fontSize * 0.8, fontWeight: FontWeight.w700, color: AppColors.navy),
      ),
    );
  }
}
