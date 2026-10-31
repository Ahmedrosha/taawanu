import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/groups_service.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/quran_style.dart';
import '../../widgets/ui.dart';
import '../groups/group_board_screen.dart' show ReadRequest;


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
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _anchors = _Anchors();
  Timer? _saveTimer;

  ReadRequest get r => widget.request;

  /// مفتاح حفظ مكان القراءة لكل ورد.
  String get _posKey => '${r.groupId}|${r.portionId ?? 'main'}|${r.fromQuarter}-${r.toQuarter}';

  GlobalKey _keyFor(int q) => _keys.putIfAbsent(q, GlobalKey.new);

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _scroll.dispose();
    super.dispose();
  }

  /// أول ما الشاشة تفتح: نرجع لآخر آية كانت أول الشاشة، أو لأول ربع لسه مسجّلتهوش.
  void _scrollToCurrent() {
    if (_scrolled) return;
    _scrolled = true;
    final saved = _AyahPos.parse(Prefs.instance.readPosition(_posKey));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (saved != null) {
        _jumpToAyah(saved);
      } else if (_read > 0 && _read < r.quarterCount) {
        _revealQuarter(r.fromQuarter + _read, then: () {});
      }
    });
  }

  double? get _viewTop {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.localToGlobal(Offset.zero).dy;
  }

  /// أول آية ظاهرة فوق في الشاشة.
  _AyahPos? _topAyah() {
    final top = _viewTop;
    if (top == null) return null;
    _AyahPos? best;
    var bestY = double.negativeInfinity;
    _AyahPos? firstBelow;
    var firstBelowY = double.infinity;
    for (final p in _anchors.paragraphs.values) {
      final rp = p.key.currentContext?.findRenderObject();
      if (rp is! RenderParagraph || !rp.attached) continue;
      final paraTop = rp.localToGlobal(Offset.zero).dy;
      for (final a in p.starts) {
        final y = paraTop + rp.getOffsetForCaret(TextPosition(offset: a.offset), Rect.zero).dy;
        if (y <= top + 4 && y > bestY) {
          best = a.pos;
          bestY = y;
        } else if (y > top + 4 && y < firstBelowY) {
          firstBelow = a.pos;
          firstBelowY = y;
        }
      }
    }
    return best ?? firstBelow;
  }

  void _savePosition() {
    final pos = _topAyah();
    if (pos != null) Prefs.instance.setReadPosition(_posKey, pos.toString());
  }

  /// بيوصل لربع حتى لو لسه مش متبني في القايمة (بيقرّب بالتقدير وبعدين بيظبط).
  void _revealQuarter(int quarter, {required VoidCallback then, int tries = 0}) {
    final ctx = _keyFor(quarter).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx);
      WidgetsBinding.instance.addPostFrameCallback((_) => then());
      return;
    }
    if (tries > 6 || !_scroll.hasClients) return;
    final frac = (quarter - r.fromQuarter) / r.quarterCount;
    _scroll.jumpTo((_scroll.position.maxScrollExtent * frac).clamp(0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealQuarter(quarter, then: then, tries: tries + 1));
  }

  /// بيخلي الآية دي أول سطر في الشاشة.
  void _jumpToAyah(_AyahPos pos) {
    _revealQuarter(pos.quarter, then: () {
      final top = _viewTop;
      if (top == null || !_scroll.hasClients) return;
      for (final p in _anchors.paragraphs.values) {
        final rp = p.key.currentContext?.findRenderObject();
        if (rp is! RenderParagraph || !rp.attached) continue;
        for (final a in p.starts) {
          if (a.pos != pos) continue;
          final y = rp.localToGlobal(Offset.zero).dy + rp.getOffsetForCaret(TextPosition(offset: a.offset), Rect.zero).dy;
          _scroll.jumpTo((_scroll.offset + y - top).clamp(0, _scroll.position.maxScrollExtent));
          return;
        }
      }
    });
  }

  /// تسجيل عدد الأرباع (للأمام أو للتراجع). الورد العادي والإضافي نفس الطريقة.
  Future<int?> _save(int value) async {
    final svc = GroupsService.instance;
    var points = 0;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      points = r.isPortion
          ? await svc.updatePortionProgress(r.groupId, r.portionId!, value)
          : await svc.updateProgress(r.groupId, value);
    });
    if (!mounted) return null;
    setState(() {
      _busy = false;
      if (ok) _read = value;
    });
    return ok ? points : null;
  }

  Future<void> _markQuarter() async {
    final t = AppLocalizations.of(context);
    final next = _read + 1;
    final finishing = next == r.quarterCount;
    // تأكيد قبل آخر ربع، عشان الضغط بالغلط.
    if (finishing && !await confirmDialog(context, title: t.confirmFinishTitle, body: t.confirmFinishBody)) return;
    if (!mounted) return;
    final points = await _save(next);
    if (points == null || !mounted) return;
    if (finishing) {
      await Prefs.instance.clearReadPosition(_posKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.earnedPoints(points))));
      context.pop();
    }
  }

  /// تراجع عن آخر ربع اتسجّل. لو الورد كان خلص، النقاط بتتشال.
  Future<void> _undo() async {
    final t = AppLocalizations.of(context);
    final wasDone = _read == r.quarterCount;
    if (wasDone && !await confirmDialog(context, title: t.undo, body: t.undoDoneConfirm)) return;
    if (!mounted) return;
    final points = await _save(_read - 1);
    if (points == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(points < 0 ? t.undoneWithPoints(-points) : t.undone),
    ));
  }

  Future<void> _changeFont(double delta) async {
    final v = (_fontSize + delta).clamp(18.0, 40.0);
    // نثبّت أول آية في الشاشة وإحنا بنكبّر أو بنصغّر.
    final anchor = _topAyah();
    setState(() => _fontSize = v);
    if (anchor != null) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToAyah(anchor));
    await Prefs.instance.setReaderFontSize(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rangeLabel(t, r.fromQuarter, r.toQuarter), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(r.groupName, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          IconButton(tooltip: t.textSize, onPressed: () => _changeFont(-2), icon: const Icon(Icons.text_decrease)),
          IconButton(tooltip: t.textSize, onPressed: () => _changeFont(2), icon: const Icon(Icons.text_increase)),
        ],
      ),
      body: FutureBuilder<QuranData>(
        future: QuranRepository.instance.loadFor(Prefs.instance.readerFont),
        builder: (context, snap) {
          final q = snap.data;
          if (q == null) return const Center(child: CircularProgressIndicator());
          _scrollToCurrent();
          // بنحفظ المكان بعد ما التمرير يقف بثانية.
          return NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              _saveTimer?.cancel();
              _saveTimer = Timer(const Duration(milliseconds: 800), _savePosition);
              return false;
            },
            child: CustomScrollView(
            key: _viewportKey,
            controller: _scroll,
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
                  sliver: SliverToBoxAdapter(child: _QuarterText(data: q, quarter: r.fromQuarter + i, fontSize: _fontSize, anchors: _anchors)),
                ),
                if (i == _read)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: FilledButton(
                        onPressed: _busy ? null : _markQuarter,
                        child: Text(i == r.quarterCount - 1 ? (r.isPortion ? t.finishPortionExtra : t.finishedPortion) : t.markQuarterDone),
                      ),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProgressLine(value: _read / r.quarterCount),
                    const SizedBox(height: 6),
                    Text(t.quartersProgress(_read, r.quarterCount), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // تراجع عن آخر ربع (لو اتسجّل بالغلط).
              TextButton.icon(
                onPressed: _busy || _read == 0 ? null : _undo,
                icon: const Icon(Icons.undo, size: 18),
                label: Text(t.undo),
              ),
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
          Expanded(child: Divider(color: AppColors.paperLine)),
          const SizedBox(width: 10),
          if (done) Icon(Icons.check_circle, size: 18, color: AppColors.statusDone),
          if (done) const SizedBox(width: 4),
          Text(label, style: TextStyle(color: AppColors.paperLabel, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: AppColors.paperLine)),
        ],
      ),
    );
  }
}

/// نص الربع: عنوان السورة والبسملة عند بداية كل سورة، وأرقام الآيات.
class _QuarterText extends StatelessWidget {
  const _QuarterText({required this.data, required this.quarter, required this.fontSize, required this.anchors});

  final QuranData data;
  final int quarter;
  final double fontSize;
  final _Anchors anchors;

  static const _digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  String _arabicNumber(int n) => n.toString().split('').map((d) => _digits[int.parse(d)]).join();

  @override
  Widget build(BuildContext context) {
    final ayahs = data.ayahsOfQuarter(quarter);
    final quranStyle = quranTextStyle(Prefs.instance.readerFont, fontSize: fontSize, color: AppColors.text);
    final markStyle = quranStyle.copyWith(fontSize: fontSize * 0.8, color: AppColors.goldInk);

    // نقسم الآيات لمجموعات حسب السورة، عشان نحط عنوان السورة قبل أول آية فيها.
    final blocks = <Widget>[];
    var spans = <InlineSpan>[];
    var starts = <_AyahStart>[];
    var length = 0;
    var paraIndex = 0;
    void flush() {
      if (spans.isEmpty) return;
      // كل فقرة ليها مفتاح وأماكن بداية آياتها، عشان نعرف أنهي آية أول الشاشة.
      final para = anchors.paragraph('$quarter:${paraIndex++}', starts);
      blocks.add(Text.rich(TextSpan(children: spans), key: para.key, textAlign: TextAlign.justify, textDirection: TextDirection.rtl));
      spans = [];
      starts = [];
      length = 0;
    }

    for (final a in ayahs) {
      if (a.number == 1) {
        flush();
        blocks.add(_SurahTitle(name: data.surahNamesAr[a.surah - 1], fontSize: fontSize));
        if (a.surah != 1 && a.surah != 9) {
          blocks.add(Text(data.basmala, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: quranStyle));
        }
      }
      starts.add(_AyahStart(_AyahPos(quarter, a.surah, a.number), length));
      final text = '${a.text} ';
      spans.add(TextSpan(text: text, style: quranStyle));
      length += text.length;
      // مصحف المدينة: رقم الآية جوه النص بشكل المصحف المطبوع.
      if (!data.numbersInText) {
        final mark = '﴿${_arabicNumber(a.number)}﴾ ';
        spans.add(TextSpan(text: mark, style: markStyle));
        length += mark.length;
      }
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
        border: Border.all(color: AppColors.accent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: GoogleFonts.amiri(fontSize: fontSize * 0.8, fontWeight: FontWeight.w700, color: AppColors.accent),
      ),
    );
  }
}

/// مكان آية: الربع والسورة ورقم الآية.
class _AyahPos {
  const _AyahPos(this.quarter, this.surah, this.ayah);

  final int quarter;
  final int surah;
  final int ayah;

  static _AyahPos? parse(String? s) {
    final p = s?.split(':');
    if (p == null || p.length != 3) return null;
    final v = p.map(int.tryParse).toList();
    if (v.contains(null)) return null;
    return _AyahPos(v[0]!, v[1]!, v[2]!);
  }

  @override
  String toString() => '$quarter:$surah:$ayah';

  @override
  bool operator ==(Object other) => other is _AyahPos && other.quarter == quarter && other.surah == surah && other.ayah == ayah;

  @override
  int get hashCode => Object.hash(quarter, surah, ayah);
}

class _AyahStart {
  const _AyahStart(this.pos, this.offset);

  final _AyahPos pos;

  /// مكان أول حرف في الآية جوه نص الفقرة.
  final int offset;
}

class _Paragraph {
  _Paragraph(this.key, this.starts);

  final GlobalKey key;
  List<_AyahStart> starts;
}

/// فقرات النص اللي على الشاشة وأماكن آياتها.
class _Anchors {
  final paragraphs = <String, _Paragraph>{};

  _Paragraph paragraph(String id, List<_AyahStart> starts) {
    final p = paragraphs.putIfAbsent(id, () => _Paragraph(GlobalKey(), starts));
    p.starts = starts;
    return p;
  }
}
