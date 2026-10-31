import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/groups_service.dart';
import '../../services/mushaf_fonts.dart';
import '../../services/mushaf_layout.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/quran_style.dart';
import '../../widgets/ui.dart';
import '../groups/group_board_screen.dart' show ReadRequest;
import 'mushaf_page.dart';


/// قراءة الورد ربع ربع، وتسجيل كل ربع لما يخلص.
/// الافتراضي صفحات زي مصحف المدينة، واللي عايز يكبّر الخط بيتحوّل لنص متصل ويقدر يرجع.
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

  /// 'pages' = صفحات المصحف، 'text' = نص متصل.
  late String _view = Prefs.instance.readerView;
  late bool _qpc = Prefs.instance.pageStyle == 'qpc';
  PageController? _pager;
  int _page = 1;
  QuranData? _pageQuran;
  MushafLayout? _layout;
  final _pointers = <int, Offset>{};
  double? _pinchStart;

  Future<(QuranData, MushafLayout?)>? _textData;
  Future<(QuranData, MushafLayout?)>? _pagesData;

  bool get _pages => _view == 'pages';

  Future<(QuranData, MushafLayout?)> get _data =>
      _pages ? _pagesData ??= _loadPages() : _textData ??= _loadText();

  /// الصفحات دايمًا بنص مصحف المدينة، عشان الكلمات تطابق التوزيع.
  Future<(QuranData, MushafLayout?)> _loadPages() async {
    final q = QuranRepository.instance.loadMadinah();
    final layout = MushafLayout.load();
    return (await q, await layout);
  }

  Future<(QuranData, MushafLayout?)> _loadText() async =>
      (await QuranRepository.instance.loadFor(Prefs.instance.readerFont), null);

  ReadRequest get r => widget.request;

  /// مفتاح حفظ مكان القراءة لكل ورد.
  String get _posKey => '${r.groupId}|${r.portionId ?? 'main'}|${r.fromQuarter}-${r.toQuarter}';

  GlobalKey _keyFor(int q) => _keys.putIfAbsent(q, GlobalKey.new);

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _scroll.dispose();
    _pager?.dispose();
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
    final pos = _pages ? _pagePosition() : _topAyah();
    if (pos != null) Prefs.instance.setReadPosition(_posKey, pos.toString());
  }

  // ---------- صفحات المصحف ----------

  int _cmp(int s1, int a1, int s2, int a2) => s1 != s2 ? s1 - s2 : a1 - a2;

  /// أول آية في الصفحة الحالية (جوه حدود الورد).
  _AyahPos? _pagePosition() {
    final q = _pageQuran, layout = _layout;
    if (q == null || layout == null) return null;
    var (s, a) = layout.firstAyahOf(_page);
    final (s1, a1) = q.quarterStart(r.fromQuarter);
    final (s2, a2) = q.quarterEnd(r.toQuarter);
    if (_cmp(s, a, s1, a1) < 0) (s, a) = (s1, a1);
    if (_cmp(s, a, s2, a2) > 0) (s, a) = (s2, a2);
    return _AyahPos(q.quarterOf(s, a).clamp(r.fromQuarter, r.toQuarter), s, a);
  }

  /// التحويل بين الصفحات والنص المتصل، من نفس الآية.
  Future<void> _setView(String view) async {
    if (view == _view) return;
    final pos = _pages ? _pagePosition() : _topAyah();
    if (pos != null) await Prefs.instance.setReadPosition(_posKey, pos.toString());
    await Prefs.instance.setReaderView(view);
    if (!mounted) return;
    final old = _pager;
    setState(() {
      _view = view;
      _pager = null;
      _scrolled = false;
      _anchors.paragraphs.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  Future<void> _enlarge() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _setView('text');
    messenger.showSnackBar(SnackBar(content: Text(t.switchedToText), duration: const Duration(seconds: 5)));
  }

  void _useHafs() {
    Prefs.instance.setPageStyle('hafs');
    setState(() => _qpc = false);
  }

  /// تكبير بصباعين على الصفحة = تحويل للنص المتصل.
  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) {
      _pointers[e.pointer] = e.position;
    } else if (e is PointerMoveEvent) {
      _pointers[e.pointer] = e.position;
    } else {
      _pointers.remove(e.pointer);
    }
    if (_pointers.length != 2) {
      _pinchStart = null;
      return;
    }
    final pts = _pointers.values.toList();
    final d = (pts[0] - pts[1]).distance;
    _pinchStart ??= d;
    if (_pinchStart! > 0 && d / _pinchStart! > 1.3) {
      _pointers.clear();
      _pinchStart = null;
      _enlarge();
    }
  }

  Widget _pagesBody(QuranData q, MushafLayout layout) {
    _pageQuran = q;
    _layout = layout;
    final (s1, a1) = q.quarterStart(r.fromQuarter);
    final (s2, a2) = q.quarterEnd(r.toQuarter);
    final first = layout.pageOf(s1, a1);
    final last = layout.endPageOf(s2, a2);
    if (_pager == null) {
      final saved = _AyahPos.parse(Prefs.instance.readPosition(_posKey));
      var start = first;
      if (saved != null) {
        start = layout.pageOf(saved.surah, saved.ayah);
      } else if (_read > 0 && _read < r.quarterCount) {
        final (s, a) = q.quarterStart(r.fromQuarter + _read);
        start = layout.pageOf(s, a);
      }
      _page = start.clamp(first, last);
      _pager = PageController(initialPage: _page - first);
      if (_qpc) MushafFonts.instance.prefetch(_page);
    }
    bool inRange(int s, int a) => _cmp(s, a, s1, a1) >= 0 && _cmp(s, a, s2, a2) <= 0;
    return Listener(
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerUp: _onPointer,
      onPointerCancel: _onPointer,
      child: Directionality(
        // المصحف بيتقلّب من اليمين للشمال حتى لو التطبيق إنجليزي.
        textDirection: TextDirection.rtl,
        child: PageView.builder(
          controller: _pager,
          itemCount: last - first + 1,
          onPageChanged: (i) {
            _page = first + i;
            if (_qpc) MushafFonts.instance.prefetch(_page);
            _saveTimer?.cancel();
            _saveTimer = Timer(const Duration(milliseconds: 800), _savePosition);
          },
          itemBuilder: (context, i) => MushafPage(
            layout: layout,
            quran: q,
            page: first + i,
            qpc: _qpc,
            inRange: inRange,
            onUseHafs: _useHafs,
          ),
        ),
      ),
    );
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
        actions: _pages
            ? [IconButton(tooltip: t.enlargeText, onPressed: _enlarge, icon: const Icon(Icons.zoom_in))]
            : [
                IconButton(tooltip: t.mushafPagesView, onPressed: () => _setView('pages'), icon: const Icon(Icons.menu_book_outlined)),
                IconButton(tooltip: t.textSize, onPressed: () => _changeFont(-2), icon: const Icon(Icons.text_decrease)),
                IconButton(tooltip: t.textSize, onPressed: () => _changeFont(2), icon: const Icon(Icons.text_increase)),
              ],
      ),
      body: FutureBuilder<(QuranData, MushafLayout?)>(
        key: ValueKey(_view),
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final (q, layout) = data;
          if (layout != null) return _pagesBody(q, layout);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // في وضع الصفحات زرار تسجيل الربع تحت على طول.
              if (_pages && _read < r.quarterCount)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: FilledButton(
                    onPressed: _busy ? null : _markQuarter,
                    child: Text(_read == r.quarterCount - 1
                        ? (r.isPortion ? t.finishPortionExtra : t.finishedPortion)
                        : '${t.markQuarterDone} · ${rangeLabel(t, r.fromQuarter + _read, r.fromQuarter + _read)}'),
                  ),
                ),
              Row(
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
