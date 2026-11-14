import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/groups_service.dart';
import '../../services/mushaf_fonts.dart';
import '../../services/mushaf_layout.dart';
import '../../services/personal_ward.dart';
import '../../services/prefs.dart';
import '../../services/recitation_player.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/tajweed_colors.dart';
import '../profile/mushaf_settings.dart';
import '../../widgets/quran_style.dart';
import '../../widgets/ui.dart';
import '../groups/group_board_screen.dart' show ReadRequest;
import 'mushaf_page.dart';
import 'recitation_bar.dart';
import 'auto_read_bar.dart';
import 'read_highlight.dart';
import '../../services/read_positions.dart';
import '../../services/reading_time.dart';
import '../../theme/highlight_colors.dart';
import '../../services/auto_reader.dart';
import 'tafsir_sheet.dart';
import '../../widgets/tour.dart';
import '../../widgets/tour_texts.dart';


/// قراءة الورد ربع ربع، وتسجيل كل ربع لما يخلص.
/// الافتراضي صفحات زي مصحف المدينة، واللي عايز يكبّر الخط بيتحوّل لنص متصل ويقدر يرجع.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.request});

  final ReadRequest request;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  late bool _qpc = Prefs.instance.pageStyle != 'hafs';
  PageController? _pager;
  int _page = 1;

  /// آخر صفحة مسموح يوصلها: صفحة نهاية الربع اللي عليه (أو آخر الورد لو خلص).
  /// بتتحسب من [_read] كل مرة، عشان الزرار تحت ميبقاش متأخر عن الصفحات.
  int get _limitPage {
    final q = _pageQuran, layout = _layout;
    if (q == null || layout == null) return 1 << 30;
    final (s2, a2) = _to(q);
    final last = layout.endPageOf(s2, a2);
    if (_read >= r.quarterCount) return last;
    final (es, ea) = q.quarterEnd(r.fromQuarter + _read);
    final (s1, a1) = _from(q);
    return layout.endPageOf(es, ea).clamp(layout.pageOf(s1, a1), last);
  }
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

  /// سورة من الورد الشخصي: القارئ بيتعامل معاها بس (من أول آية لآخر آية).
  int? get _goal => r.personal && r.portionId != null ? r.startSurah : null;
  (int, int) _from(QuranData q) => _goal == null ? q.quarterStart(r.fromQuarter) : (_goal!, 1);
  (int, int) _to(QuranData q) => _goal == null ? q.quarterEnd(r.toQuarter) : (_goal!, q.ayahCount(_goal!));

  /// مفتاح حفظ مكان القراءة لكل ورد.
  String get _posKey => '${r.groupId}|${r.portionId ?? 'main'}|${r.fromQuarter}-${r.toQuarter}';

  GlobalKey _keyFor(int q) => _keys.putIfAbsent(q, GlobalKey.new);

  final _audio = RecitationPlayer.instance;
  final _auto = AutoReader.instance;
  (int, int)? _followed;
  (int, int)? _savedCur;

  /// الآية المنوّرة دلوقتي: من التلاوة أو من القراءة التلقائية.
  (int, int)? get _current => _audio.current ?? _auto.current;

  /// اللي بيتنوّر: الآية في التلاوة، وفي القراءة التلقائية حسب الاختيار (آية / كلمة / بدون).
  ReadHighlight? get _highlight {
    final a = _audio.current;
    if (a != null) return ReadHighlight(a.$1, a.$2);
    final c = _auto.current;
    if (c == null) {
      final f = _flash;
      return f == null ? null : ReadHighlight(f.$1, f.$2);
    }
    return switch (_auto.mode) {
      'none' || 'manual' => null,
      'word' => ReadHighlight(c.$1, c.$2, _auto.word),
      _ => ReadHighlight(c.$1, c.$2),
    };
  }

  /// التلاوة أو القراءة التلقائية شغالة.
  bool get _following => _audio.active || _auto.active;
  QuranData? _textQuran;

  /// لما التلاوة تنتقل لآية جديدة: الصفحة بتقلّب لوحدها (أو النص بينزل).
  void _onAudio() {
    if (!mounted) return;
    final cur = _current;
    setState(() {});
    // آخر آية منوّرة بتتحفظ، عشان الورد يفتح عندها المرة الجاية.
    if (cur != null && cur != _savedCur) {
      _savedCur = cur;
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 600), _savePosition);
    }
    if (!_pages) {
      _followText(cur);
      return;
    }
    if (cur == null || cur == _followed) return;
    _followed = cur;
    final (s, a) = cur;
    if (_pages) {
      final layout = _layout, q = _pageQuran;
      if (layout == null || q == null || !(_pager?.hasClients ?? false)) return;
      final (s1, a1) = _from(q);
      final first = layout.pageOf(s1, a1);
      final p = layout.pageOf(s, a);
      if (p != _page && p <= _limitPage) _pager!.animateToPage(p - first, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      final q = _textQuran;
      if (q == null) return;
      _jumpToAyah(_AyahPos(q.quarterOf(s, a).clamp(r.fromQuarter, r.toQuarter), s, a));
    }
  }

  // ---------- متابعة النص المتصل ----------
  // الشاشة بتطلع لفوق بنعومة وبشكل مستمر: أول الآية عند "خط القراية" لما تبدأ،
  // وآخرها عنده لما تخلص، فالآية اللي بعدها بتبدأ في نفس المكان من غير نطّ.


  void _followText((int, int)? cur) {
    // التلاوة والقراءة الصامتة: الصفحة بتطلع بنعومة من الـticker (مش آية آية).
    _syncTicker();
  }


  // ---------- القراءة الصامتة في النص المتصل: الشاشة بسرعة ثابتة ----------
  late final _ticker = createTicker(_onTick);
  Duration? _lastTick;
  DateTime _userScrolledAt = DateTime(2000);
  DateTime _catchUpUntil = DateTime(2000);
  final _paraRate = <String, (double, double)>{}; // فقرة → (طولها، بكسل لكل كلمة)

  // مسافة فوق وتحت النص وقت القراءة الصامتة.
  double _autoPadTop = 0, _autoPadBottom = 0;

  /// أول ما القراءة الصامتة تبدأ: المسافة بتتحط والكلمة بتنزل لمكان القراية (تلت الشاشة).
  /// ولما تقف: المسافة بتتشال من غير ما النص يتحرك.
  void _syncAutoPad() {
    if (_pages || !_scroll.hasClients) return;
    final on = _auto.active;
    if (on == (_autoPadTop > 0)) return;
    final h = _scroll.position.viewportDimension;
    final top = on ? h * 0.3 : 0.0;
    final shift = top - _autoPadTop;
    setState(() {
      _autoPadTop = top;
      _autoPadBottom = on ? h * 0.7 : 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      pos.jumpTo((pos.pixels + shift).clamp(0.0, pos.maxScrollExtent));
      if (on) _alignToLine();
    });
  }

  /// بينزّل الكلمة اللي عليها الدور لمكان القراية بنعومة.
  /// بيعيد المحاولة لحد ما النص يتبني والكلمة تبقى فعلًا في مكانها.
  void _alignToLine([int attempt = 0]) {
    // اليدوي: بيبدأ من مكان الشاشة ومبيتحركش لوحده لمكان الكلمة.
    if (!mounted || _pages || !_auto.active || _auto.mode == 'manual') return;
    final top = _viewTop;
    final focus = _wordY();
    if (top == null || focus == null || !_scroll.hasClients) {
      if (attempt < 15) Future.delayed(const Duration(milliseconds: 150), () => _alignToLine(attempt + 1));
      return;
    }
    final pos = _scroll.position;
    final error = focus.$1 - (top + pos.viewportDimension * 0.3);
    if (error.abs() < 12) return;
    _catchUpUntil = DateTime.now().add(const Duration(milliseconds: 450));
    _scroll
        .animateTo((pos.pixels + error).clamp(0.0, pos.maxScrollExtent),
            duration: const Duration(milliseconds: 400), curve: Curves.easeInOut)
        .then((_) {
      if (attempt < 15) Future.delayed(const Duration(milliseconds: 100), () => _alignToLine(attempt + 1));
    });
  }

  void _syncTicker() {
    _syncAutoPad();
    // اليدوي: الشاشة بتكمّل لحد آخر النص حتى لو العدّاد وصل آخر الربع قبلها.
    final manualRun = _auto.active && _auto.mode == 'manual' && _auto.waiting;
    final run = !_pages && ((_auto.active && (_auto.playing || manualRun)) || (_audio.active && _audio.playing));
    if (run && !_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// مكان الكلمة اللي عليها الدور على الشاشة (y)، وبكسل لكل كلمة في فقرتها.
  (double, double)? _wordY() {
    final cur = _auto.current;
    final q = _textQuran;
    if (cur == null || q == null) return null;
    final (s, a) = cur;
    for (final e in _anchors.paragraphs.entries) {
      final p = e.value;
      final rp = p.key.currentContext?.findRenderObject();
      if (rp is! RenderParagraph || !rp.attached) continue;
      for (final st in p.starts) {
        if (st.pos.surah != s || st.pos.ayah != a) continue;
        final starts = ayahWordStarts(q.ayahText(s, a));
        final w = (_auto.word ?? 0).clamp(0, starts.isEmpty ? 0 : starts.length - 1);
        final off = st.offset + (starts.isEmpty ? 0 : starts[w]);
        final y = rp.localToGlobal(Offset.zero).dy + rp.getOffsetForCaret(TextPosition(offset: off), Rect.zero).dy;
        // سرعة الشاشة من الفقرة كلها (طولها ÷ عدد كلماتها)، فمبتتغيرش من آية لآية.
        final h = rp.size.height;
        var rate = _paraRate[e.key];
        if (rate == null || rate.$1 != h) {
          var words = 0;
          for (final x in p.starts) {
            words += ayahWordStarts(q.ayahText(x.pos.surah, x.pos.ayah)).length;
          }
          rate = (h, words == 0 ? 0 : h / words);
          _paraRate[e.key] = rate;
        }
        return (y, rate.$2);
      }
    }
    return null;
  }

  int _touches = 0;

  void _pointerUp() {
    if (_touches > 0) _touches--;
    _userScrolledAt = DateTime.now();
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null || !mounted || _pages || !_scroll.hasClients) return;
    // صباعه على الشاشة، أو الشاشة لسه بتتزحلق من سحبته: منلمسش التمرير.
    if (_touches > 0 || _scroll.position.isScrollingNotifier.value) return;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    final now = DateTime.now();
    if (!_audio.active && _auto.mode == 'manual') {
      _manualTick(dt, now);
      return;
    }
    if (now.difference(_userScrolledAt) < const Duration(milliseconds: 1500) || now.isBefore(_catchUpUntil)) return;
    final top = _viewTop;
    final pos = _scroll.position;
    if (top == null) return;
    if (_audio.active) {
      _followRecitation(dt, top, pos, now);
      return;
    }
    final focus = _wordY();
    if (focus == null) {
      // الآية لسه مش متبنية: نروح لها.
      final cur = _auto.current, q = _textQuran;
      if (cur != null && q != null) {
        _catchUpUntil = now.add(const Duration(milliseconds: 600));
        _jumpToAyah(_AyahPos(q.quarterOf(cur.$1, cur.$2).clamp(r.fromQuarter, r.toQuarter), cur.$1, cur.$2), line: 0.3);
      }
      return;
    }
    final (y, pxPerWord) = focus;
    final h = pos.viewportDimension;
    final line = top + h * 0.3;
    final error = y - line;
    // الكلمة بعيدة عن التلت اللي فوق (مثلًا مستخبية فوق في الأول): ننقلها له بنعومة.
    if (error.abs() > h * 0.2) {
      // بعيد قوي عن مكان القراية: نرجع له بنعومة.
      _catchUpUntil = now.add(const Duration(milliseconds: 450));
      _scroll.animateTo((pos.pixels + error).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      return;
    }
    final wordsPerSec = AutoReader.wordsPerMinute * _auto.speed / 60;
    // تصحيح بسيط جدًا عشان الكلمة تفضل قدام العين، من غير ما السرعة تتغير بشكل يتحس.
    final factor = (1 + error / (h * 0.6)).clamp(0.85, 1.15);
    final next = (pos.pixels + wordsPerSec * pxPerWord * factor * dt).clamp(0.0, pos.maxScrollExtent);
    if (next != pos.pixels) _scroll.jumpTo(next);
  }

  // ---------- الوضع اليدوي ----------
  bool _userScrolling = false;
  double _manualRate = 0;
  DateTime _manualSyncAt = DateTime(2000);

  /// الوضع اليدوي: الشاشة بتطلع بسرعة القراءة من غير تنوير. لو حرّكها بإيده بتقف وهو ماسكها،
  /// وبعدها بتكمّل من المكان الجديد (مش بترجع للي كانت فيه). مكان القراءة بيمشي ورا الشاشة.
  void _manualTick(double dt, DateTime now) {
    if (_userScrolling || now.difference(_userScrolledAt) < const Duration(milliseconds: 300)) return;
    final top = _viewTop;
    if (top == null) return;
    final pos = _scroll.position;
    final rate = _rateAt(top + pos.viewportDimension * 0.3) ?? _manualRate;
    if (rate <= 0) return;
    _manualRate = rate;
    final wordsPerSec = AutoReader.wordsPerMinute * _auto.speed / 60;
    final next = (pos.pixels + wordsPerSec * rate * dt).clamp(0.0, pos.maxScrollExtent);
    if (next != pos.pixels) _scroll.jumpTo(next);
    if (now.difference(_manualSyncAt) > const Duration(milliseconds: 400)) {
      _manualSyncAt = now;
      final a = _lineAyah();
      if (a != null) _auto.seek(a.surah, a.ayah);
    }
  }

  /// بكسل لكل كلمة في الفقرة اللي عند الخط ده، ولو الخط على اسم سورة أو بسملة أو مسافة فاضية: أقرب فقرة.
  double? _rateAt(double y) {
    final q = _textQuran;
    if (q == null) return null;
    MapEntry<String, _Paragraph>? best;
    var bestDist = double.infinity;
    for (final e in _anchors.paragraphs.entries) {
      final rp = e.value.key.currentContext?.findRenderObject();
      if (rp is! RenderParagraph || !rp.attached || !rp.hasSize) continue;
      final t0 = rp.localToGlobal(Offset.zero).dy;
      final h = rp.size.height;
      final dist = y < t0 ? t0 - y : (y > t0 + h ? y - (t0 + h) : 0.0);
      if (dist < bestDist) {
        bestDist = dist;
        best = e;
      }
    }
    final e = best;
    if (e == null) return null;
    final rp = e.value.key.currentContext!.findRenderObject()! as RenderParagraph;
    final h = rp.size.height;
    var rate = _paraRate[e.key];
    if (rate == null || rate.$1 != h) {
      var words = 0;
      for (final x in e.value.starts) {
        words += ayahWordStarts(q.ayahText(x.pos.surah, x.pos.ayah)).length;
      }
      rate = (h, words == 0 ? 0.0 : h / words);
      _paraRate[e.key] = rate;
    }
    return rate.$2;
  }

  /// التلاوة في النص المتصل: الصفحة بتطلع بنعومة كإن فيه كلمة مستخبية ماشية جوه الآية على قد صوتها،
  /// والمكان ده بيفضل في التلت اللي فوق. الآية الطويلة (خط كبير) بتبدأ من أول كلمة وتطلع مع القارئ.
  void _followRecitation(double dt, double top, ScrollPosition pos, DateTime now) {
    final cur = _audio.current;
    if (cur == null) return;
    final span = _ayahSpan(cur);
    final h = pos.viewportDimension;
    final line = top + h * 0.3;
    if (span == null) {
      final q = _textQuran;
      if (q != null) {
        _catchUpUntil = now.add(const Duration(milliseconds: 600));
        _jumpToAyah(_AyahPos(q.quarterOf(cur.$1, cur.$2).clamp(r.fromQuarter, r.toQuarter), cur.$1, cur.$2), line: 0.3);
      }
      return;
    }
    // نسبة اللي اتقرا من الآية من الصوت (البسملة = لسه في أولها).
    final d = _audio.duration;
    var frac = 0.0;
    if (d != null && d.inMilliseconds > 0 && !_audio.onBasmala) {
      frac = (_audio.position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
    }
    final y = span.$1 + (span.$2 - span.$1) * frac;
    final error = y - line;
    if (error.abs() > h * 0.35) {
      _catchUpUntil = now.add(const Duration(milliseconds: 450));
      _scroll.animateTo((pos.pixels + error).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      return;
    }
    // بنقرّب ناحية المكان بنعومة كل فريم (من غير قفزات).
    final next = (pos.pixels + error * (dt * 4).clamp(0.0, 1.0)).clamp(0.0, pos.maxScrollExtent);
    if ((next - pos.pixels).abs() > 0.1) _scroll.jumpTo(next);
  }

  /// أول الآية وآخرها على الشاشة (y)، لو الآية متبنية.
  (double, double)? _ayahSpan((int, int) cur) {
    final (s, a) = cur;
    for (final p in _anchors.paragraphs.values) {
      final rp = p.key.currentContext?.findRenderObject();
      if (rp is! RenderParagraph || !rp.attached) continue;
      final starts = [...p.starts]..sort((x, y) => x.offset.compareTo(y.offset));
      for (var i = 0; i < starts.length; i++) {
        if (starts[i].pos.surah != s || starts[i].pos.ayah != a) continue;
        final top = rp.localToGlobal(Offset.zero).dy;
        double yAt(int offset) => top + rp.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
        final y0 = yAt(starts[i].offset);
        final y1 = i + 1 < starts.length ? yAt(starts[i + 1].offset) : top + rp.size.height;
        return (y0, y1);
      }
    }
    return null;
  }


  /// الآية دي ظاهرة دلوقتي؟ (في صفحتها، أو جوه الشاشة في النص المتصل).
  bool _isOnScreen(int s, int a) {
    if (_pages) return _layout != null && _layout!.pageOf(s, a) <= _page && _layout!.endPageOf(s, a) >= _page;
    final span = _ayahSpan((s, a));
    final top = _viewTop;
    if (span == null || top == null || !_scroll.hasClients) return false;
    return span.$2 > top && span.$1 < top + _scroll.position.viewportDimension;
  }

  /// كل آيات الربع ده بالترتيب.
  List<(int, int)> _quarterAyahs(QuranData q, int quarter) => [for (final a in q.ayahsOfQuarter(quarter)) (a.surah, a.number)];

  /// الآيات من مكان القراءة الحالي لحد آخر الربع اللي عليه (التلاوة بتقف هناك).
  List<(int, int)> _recitationAyahs({(int, int)? from}) {
    final q = _pages ? _pageQuran : _textQuran;
    if (q == null) return const [];
    final (s1, a1) = _from(q);
    final endQuarter = _read >= r.quarterCount ? r.toQuarter : r.fromQuarter + _read;
    var (s2, a2) = _goal != null ? _to(q) : q.quarterEnd(endQuarter);
    var start = from;
    if (start == null) {
      // آخر آية وقفت عندها لو لسه قدامك، وإلا أول الشاشة.
      final saved = _AyahPos.parse(ReadPositions.instance.local(_posKey));
      final pos = saved != null && _isOnScreen(saved.surah, saved.ayah) ? saved : (_pages ? _pagePosition() : _topAyah());
      start = pos == null ? (s1, a1) : (pos.surah, pos.ayah);
    }
    var (s, a) = start;
    if (_cmp(s, a, s1, a1) < 0) (s, a) = (s1, a1);
    if (_cmp(s, a, s2, a2) > 0) (s, a) = (s1, a1);
    // المصحف الحر: التلاوة والقراءة التلقائية جزء واحد (٨ أرباع) من مكانك، مش لآخر المصحف.
    if (r.personal && _goal == null) (s2, a2) = q.quarterEnd((q.quarterOf(s, a) + 7).clamp(1, 240));
    final out = <(int, int)>[];
    while (_cmp(s, a, s2, a2) <= 0) {
      out.add((s, a));
      if (a < q.ayahCount(s)) {
        a++;
      } else {
        s++;
        a = 1;
      }
    }
    return out;
  }

  /// (سورة، آية، عدد الكلمات) للقراءة التلقائية.
  List<(int, int, int)> _withWords(List<(int, int)> ayahs) {
    final q = _pages ? _pageQuran : _textQuran;
    if (q == null) return const [];
    final layout = _layout;
    int words(int s, int a) {
      if (_pages && layout != null) return layout.wordCount(s, a);
      return ayahWordStarts(q.ayahText(s, a)).length;
    }

    return [for (final (s, a) in ayahs) (s, a, words(s, a).clamp(1, 1000))];
  }

  Future<void> _startAutoRead({(int, int)? from}) async {
    final ayahs = _withWords(_recitationAyahs(from: from));
    if (ayahs.isEmpty) return;
    _followed = null;
    if (_audio.active) await _audio.stop();
    _auto.play(ayahs);
    if (!_pages) WidgetsBinding.instance.addPostFrameCallback((_) => _alignToLine());
    if (mounted) {
      Tour.schedule(context, 'autoread', () => [
            TourStep(_kMode, tourText(context, 'auto.mode')),
            TourStep(_kSpeed, tourText(context, 'auto.speed')),
          ], delay: const Duration(milliseconds: 600));
    }
  }

  String _ayahTitle(int s, int a) {
    final q = _pages ? _pageQuran : _textQuran;
    final name = q?.surahName(s, 'ar').replaceFirst(RegExp(r'^سُوْرَةُ\s*'), '') ?? '';
    return '$name $a';
  }

  Future<void> _startRecitation({(int, int)? from}) async {
    final ayahs = _recitationAyahs(from: from);
    if (ayahs.isEmpty) return;
    _followed = null;
    if (_auto.active) _auto.stop();
    await _audio.play(ayahs, title: _ayahTitle);
    if (mounted) {
      Tour.schedule(context, 'recitation', () => [
            TourStep(_kReciter, tourText(context, 'recite.reciter')),
            TourStep(_kDownload, tourText(context, 'recite.download'), radius: 24),
          ], delay: const Duration(milliseconds: 600));
    }
  }

  // الجولة التعريفية.
  final _kPage = GlobalKey(), _kPlay = GlobalKey(), _kView = GlobalKey(), _kMode = GlobalKey(), _kMark = GlobalKey(), _kUndo = GlobalKey();
  final _kReciter = GlobalKey(), _kDownload = GlobalKey(), _kAuto = GlobalKey(), _kSpeed = GlobalKey();

  /// التلاوة شغالة والتطبيق مفتوح بس: لو خرج من التطبيق أو قفل الشاشة بتقف مؤقتًا.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // التطبيق راح للخلفية أو اتقفل وهو في المصحف: نحفظ الآية دلوقتي.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _savePosition();
      ReadPositions.instance.flush();
    }
    if (state == AppLifecycleState.resumed) {
      ReadingTime.instance.resumeCounting();
    } else {
      ReadingTime.instance.pauseCounting();
    }
    if (state != AppLifecycleState.resumed && _audio.playing) _audio.pause();
    if (state != AppLifecycleState.resumed && _auto.playing) _auto.pause();
  }

  @override
  void initState() {
    super.initState();
    _audio.addListener(_onAudio);
    _auto.addListener(_onAudio);
    // أرقام صفحات مصحف المدينة في النص المتصل.
    MushafLayout.load().then((_) {
      if (mounted && !_pages) setState(() {});
    });
    _scroll.addListener(_onScrollPages);
    if (r.personal) {
      PersonalWard.instance.resetCursor();
    }
    _loadRemotePosition();
    WidgetsBinding.instance.addObserver(this);
    // وقت التلاوة: بيتحسب طول ما المصحف قدامك وفيه حركة أو تلاوة أو قراءة تلقائية.
    ReadingTime.instance.begin(() => _audio.playing || _auto.playing);
    // الشاشة متقفلش طول ما المصحف مفتوح (قراءة أو تلاوة).
    WakelockPlus.enable();
    if (!r.personal) {
      Tour.schedule(context, 'reader', () => [
          TourStep(_kPage, tourText(context, 'reader.page'), padding: 0),
          TourStep(_kPlay, tourText(context, 'reader.play'), radius: 24),
          TourStep(_kAuto, tourText(context, 'reader.auto'), radius: 24),
          TourStep(_kView, tourText(context, 'reader.view'), radius: 24),
          TourStep(_kMark, tourText(context, 'reader.mark')),
          TourStep(_kUndo, tourText(context, 'reader.undo')),
        ], delay: const Duration(milliseconds: 1200));
    }
    // الجولة بتشرح الضغط على الآية، فالتلميح القديم للي شاف الجولة قبل كده بس.
    if (!Prefs.instance.tourDone('reader')) Prefs.instance.setTafsirTipShown();
    if (!Prefs.instance.tafsirTipShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).tafsirTip),
          duration: const Duration(seconds: 5),
        ));
        Prefs.instance.setTafsirTipShown();
      });
    }
  }

  @override
  void dispose() {
    _audio.removeListener(_onAudio);
    _auto.removeListener(_onAudio);
    _ticker.dispose();
    ReadingTime.instance.end();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    // التلاوة بتقف لما يقفل شاشة القراءة.
    // المكان بيتحفظ الأول (الآية المنوّرة)، وبعدين التلاوة تقف.
    _saveTimer?.cancel();
    _closing = true;
    _savePosition();
    ReadPositions.instance.flush();
    _flashTimer?.cancel();
    if (_audio.active) _audio.stop();
    if (_auto.active) _auto.stop();
    _pageTimer?.cancel();
    _scroll.dispose();
    _pager?.dispose();
    super.dispose();
  }

  /// المكان اللي القارئ يفتح عنده: السورة المطلوبة في المصحف الحر، وإلا آخر مكان محفوظ.
  bool _launched = false;

  _AyahPos? _launchPos(QuranData? q) {
    final saved = _AyahPos.parse(ReadPositions.instance.local(_posKey));
    // السورة المطلوبة لأول فتحة بس: بعد كده (مثلًا التحويل بين الصفحات والنص) المكان المحفوظ.
    if (r.personal && r.startSurah != null && q != null && !_launched) {
      _launched = true;
      // سورة من الورد الشخصي: لو وقفت جواها النهارده نكمّل من هناك، وإلا من أولها.
      if (r.portionId != null && saved != null && saved.surah == r.startSurah) {
        final at = Prefs.instance.readPositionAt(_posKey);
        final d = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at), n = DateTime.now();
        if (d != null && d.year == n.year && d.month == n.month && d.day == n.day) return saved;
      }
      final s = r.startSurah!, a = r.startAyah ?? 1;
      return _AyahPos(q.quarterOf(s, a), s, a);
    }
    return saved;
  }

  // ---------- المصحف الحر في النص المتصل: جزء واحد (٨ أرباع) في المرة ----------
  // كل القرآن في قايمة واحدة تقيل جدًا، فبنعرض الجزء اللي إنت فيه وبننقل بين الأجزاء.
  int _winFrom = 1;

  int _windowStart(int quarter) => ((quarter.clamp(1, 240) - 1) ~/ 8) * 8 + 1;

  /// أول وآخر ربع في قايمة النص (بالترتيب من صفر): السورة بس، أو الجزء المعروض، أو الورد كله.
  int _listStart(QuranData q) => _goal != null ? q.quarterOf(_goal!, 1) - 1 : (r.personal ? _winFrom - 1 : 0);
  int _listEnd(QuranData q) =>
      _goal != null ? q.quarterOf(_goal!, q.ayahCount(_goal!)) - 1 : (r.personal ? _winFrom + 6 : r.quarterCount - 1);

  void _shiftWindow(int from, {bool toEnd = false}) {
    setState(() => _winFrom = _windowStart(from));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(toEnd ? _scroll.position.maxScrollExtent : 0);
    });
  }

  /// أول ما الشاشة تفتح: نرجع لآخر آية كانت أول الشاشة، أو لأول ربع لسه مسجّلتهوش.
  void _scrollToCurrent() {
    if (_scrolled) return;
    _scrolled = true;
    final saved = _launchPos(_textQuran);
    if (r.personal) _winFrom = _windowStart(saved?.quarter ?? 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (saved != null) {
        // آخر آية وقفت عندها، في التلت اللي فوق، ومنوّرة لحظة عشان تعرف إنت فين.
        _jumpToAyah(saved, line: 0.3);
        if (!_following && mounted) setState(() => _flashAyah(saved));
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

  /// مستند مكان القراءة على السيرفر: لكل ختمة (ولكل ورد إضافي لوحده).
  String get _posDoc => '${r.groupId}_${r.portionId ?? 'main'}';

  void _storePosition(_AyahPos pos) => ReadPositions.instance.save(docId: _posDoc, key: _posKey, pos: pos.toString());

  /// مكان القراءة: الآية المنوّرة لو التلاوة أو القراءة الصامتة شغالة. من غيرهم:
  /// في النص المتصل الآية اللي عند خط القراية (التلت اللي فوق)، وفي الصفحات الآية المحفوظة
  /// لو لسه في نفس الصفحة (عشان مترجعش لأول الصفحة)، وإلا أول آية فيها.
  _AyahPos? _readingPosition() {
    final cur = _current;
    final q = _pages ? _pageQuran : _textQuran;
    if (cur != null && q != null) {
      final (s, a) = cur;
      return _AyahPos(q.quarterOf(s, a).clamp(r.fromQuarter, r.toQuarter), s, a);
    }
    if (_pages) {
      final saved = _AyahPos.parse(ReadPositions.instance.local(_posKey));
      if (saved != null && _isOnScreen(saved.surah, saved.ayah)) return saved;
      return _pagePosition();
    }
    return _lineAyah() ?? _topAyah();
  }

  /// الآية اللي عند خط القراية (تلت الشاشة من فوق) في النص المتصل.
  /// رقم الصفحة (أو الصفحتين) اللي ظاهرين في النص المتصل.
  String? _pageLabel;
  Timer? _pageTimer;

  void _onScrollPages() {
    if (_pageTimer?.isActive ?? false) return;
    _pageTimer = Timer(const Duration(milliseconds: 150), _updatePageLabel);
  }

  /// الآية اللي عند خط معيّن في الشاشة (٠ = فوق، ١ = تحت).
  _AyahPos? _ayahAtFraction(double f) {
    final top = _viewTop;
    if (top == null || !_scroll.hasClients) return null;
    final line = top + _scroll.position.viewportDimension * f;
    _AyahPos? best;
    var bestY = double.negativeInfinity;
    for (final p in _anchors.paragraphs.values) {
      final rp = p.key.currentContext?.findRenderObject();
      if (rp is! RenderParagraph || !rp.attached) continue;
      final paraTop = rp.localToGlobal(Offset.zero).dy;
      for (final a in p.starts) {
        final y = paraTop + rp.getOffsetForCaret(TextPosition(offset: a.offset), Rect.zero).dy;
        if (y <= line && y > bestY) {
          best = a.pos;
          bestY = y;
        }
      }
    }
    return best;
  }

  void _updatePageLabel() {
    if (!mounted || _pages) return;
    final layout = MushafLayout.cached;
    final a = _ayahAtFraction(0.02), b = _ayahAtFraction(0.95);
    String? label;
    if (layout != null && a != null) {
      final p1 = layout.pageOf(a.surah, a.ayah);
      final p2 = b == null ? p1 : layout.pageOf(b.surah, b.ayah);
      final t = AppLocalizations.of(context);
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      String n(int v) => ar ? arabicDigits(v) : '$v';
      label = p2 > p1 ? t.pageRangeLabel(n(p1), n(p2)) : t.pageLabel(n(p1));
    }
    if (label != _pageLabel) setState(() => _pageLabel = label);
  }

  _AyahPos? _lineAyah() {
    final top = _viewTop;
    if (top == null || !_scroll.hasClients) return null;
    final line = top + _scroll.position.viewportDimension * 0.3;
    _AyahPos? best;
    var bestY = double.negativeInfinity;
    for (final p in _anchors.paragraphs.values) {
      final rp = p.key.currentContext?.findRenderObject();
      if (rp is! RenderParagraph || !rp.attached) continue;
      final paraTop = rp.localToGlobal(Offset.zero).dy;
      for (final a in p.starts) {
        final y = paraTop + rp.getOffsetForCaret(TextPosition(offset: a.offset), Rect.zero).dy;
        if (y <= line + 6 && y > bestY) {
          best = a.pos;
          bestY = y;
        }
      }
    }
    return best;
  }

  void _savePosition() {
    final pos = _readingPosition();
    if (pos != null) _storePosition(pos);
    if (r.personal) _trackPersonal(pos);
  }

  /// الشاشة بتتقفل: مينفعش نعرض رسالة ساعتها.
  bool _closing = false;

  /// المصحف الحر: الصفحة الحالية بتتحسب مقروءة، والسور اللي كملت النهارده بتتعلّم في الورد الشخصي.
  void _trackPersonal(_AyahPos? pos) {
    final layout = _layout ?? MushafLayout.cached;
    final q = _pageQuran ?? _textQuran;
    if (layout == null || q == null) return;
    final page = _pages ? _page : (pos == null ? null : layout.pageOf(pos.surah, pos.ayah));
    if (page == null) return;
    final done = PersonalWard.instance.notePage(page, layout, q);
    if (done.isEmpty || !mounted || _closing) return;
    final t = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    final names = [for (final s in done) en ? q.surahNamesEn[s - 1] : q.surahNamesAr[s - 1]];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.personalDoneToast(names.join(', ')))));
  }

  // ---------- تنوير آخر آية لحظة لما المصحف يفتح ----------
  (int, int)? _flash;
  Timer? _flashTimer;

  void _flashAyah(_AyahPos pos) {
    _flash = (pos.surah, pos.ayah);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  /// المكان اللي على السيرفر لو أحدث (مثلًا قريت من موبايل تاني): نروح له.
  Future<void> _loadRemotePosition() async {
    if (r.personal && r.startSurah != null) return;
    final remote = await ReadPositions.instance.remoteIfNewer(docId: _posDoc, key: _posKey);
    final pos = _AyahPos.parse(remote);
    if (pos == null || !mounted || _following) return;
    await Prefs.instance.setReadPosition(_posKey, remote!);
    if (!mounted) return;
    setState(() => _flashAyah(pos));
    if (_pages) {
      final layout = _layout, q = _pageQuran;
      if (layout == null || q == null || !(_pager?.hasClients ?? false)) return;
      final (s1, a1) = _from(q);
      final target = layout.pageOf(pos.surah, pos.ayah).clamp(layout.pageOf(s1, a1), _limitPage);
      _pager!.jumpToPage(target - layout.pageOf(s1, a1));
    } else {
      _jumpToAyah(pos, line: 0.3);
    }
  }

  // ---------- صفحات المصحف ----------

  int _cmp(int s1, int a1, int s2, int a2) => s1 != s2 ? s1 - s2 : a1 - a2;

  /// أول آية في الصفحة الحالية (جوه حدود الورد).
  _AyahPos? _pagePosition() {
    final q = _pageQuran, layout = _layout;
    if (q == null || layout == null) return null;
    var (s, a) = layout.firstAyahOf(_page);
    final (s1, a1) = _from(q);
    final (s2, a2) = _to(q);
    if (_cmp(s, a, s1, a1) < 0) (s, a) = (s1, a1);
    if (_cmp(s, a, s2, a2) > 0) (s, a) = (s2, a2);
    return _AyahPos(q.quarterOf(s, a).clamp(r.fromQuarter, r.toQuarter), s, a);
  }

  /// التحويل بين الصفحات والنص المتصل، من نفس الآية.
  Future<void> _setView(String view) async {
    if (view == _view) return;
    // التلاوة والقراءة الصامتة بيكمّلوا من غير ما يقفوا، والشكل الجديد بيفتح على الآية المنوّرة.
    final pos = _readingPosition();
    if (pos != null) _storePosition(pos);
    await Prefs.instance.setReaderView(view);
    if (!mounted) return;
    final old = _pager;
    setState(() {
      _view = view;
      _pager = null;
      _scrolled = false;
      _anchors.paragraphs.clear();
      _paraRate.clear();
      _autoPadTop = 0;
      _autoPadBottom = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _afterViewReady();
  }

  /// بعد ما الشكل الجديد يتحمّل: القراءة الصامتة بتكمّل من نفس الكلمة (عدد الكلمات بيختلف
  /// بين الصفحات والنص)، والشاشة بتروح للآية المنوّرة على طول.
  Future<void> _afterViewReady() async {
    for (var i = 0; i < 40 && mounted; i++) {
      final ready = _pages ? (_layout != null && _pageQuran != null && (_pager?.hasClients ?? false)) : (_textQuran != null && _anchors.paragraphs.isNotEmpty);
      if (ready) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    if (_auto.active) _auto.remap(_withWords([for (final (s, a, _) in _auto.items) (s, a)]));
    _followed = null;
    _onAudio();
    if (!_pages && _auto.active) _alignToLine();
  }

  Future<void> _enlarge() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _setView('text');
    messenger.showSnackBar(SnackBar(content: Text(t.switchedToText), duration: const Duration(seconds: 5)));
  }

  /// الضغط على آية: قايمة صغيرة: استمع من هنا، أو التفسير.
  Future<void> _ayahMenu(int surah, int ayah) async {
    final t = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(_ayahTitle(surah, ayah), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(leading: const Icon(Icons.play_circle_outline), title: Text(t.listenFromHere), onTap: () => Navigator.pop(context, 'listen')),
            ListTile(leading: const Icon(Icons.visibility_outlined), title: Text(t.autoReadFromHere), onTap: () => Navigator.pop(context, 'auto')),
            ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text(t.tafsir), onTap: () => Navigator.pop(context, 'tafsir')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'listen') await _startRecitation(from: (surah, ayah));
    if (choice == 'auto') await _startAutoRead(from: (surah, ayah));
    if (choice == 'tafsir') _openTafsir(surah, ayah);
  }

  void _openTafsir(int surah, int ayah) =>
      showTafsirSheet(context, surah: surah, ayah: ayah, onPlay: (s, a) => _startRecitation(from: (s, a)));

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
    final (s1, a1) = _from(q);
    final (s2, a2) = _to(q);
    final first = layout.pageOf(s1, a1);
    final last = layout.endPageOf(s2, a2);
    // القارئ مبيعديش الربع اللي عليه غير لما يسجّله.
    final allDone = _read >= r.quarterCount;
    final (es, ea) = allDone ? (s2, a2) : q.quarterEnd(r.fromQuarter + _read);
    final limit = allDone ? last : layout.endPageOf(es, ea).clamp(first, last);
    if (_pager == null) {
      final saved = _launchPos(q);
      var start = first;
      if (saved != null) {
        start = layout.pageOf(saved.surah, saved.ayah);
        if (!_following) _flashAyah(saved);
      } else if (_read > 0 && _read < r.quarterCount) {
        final (s, a) = q.quarterStart(r.fromQuarter + _read);
        start = layout.pageOf(s, a);
      }
      _page = start.clamp(first, limit);
      _pager = PageController(initialPage: _page - first);
      if (r.personal) WidgetsBinding.instance.addPostFrameCallback((_) => _trackPersonal(null));
      if (_qpc) MushafFonts.instance.prefetch(_page);
    }
    // بعد التراجع: لو واقف بعد الحد الجديد نرجع لصفحة نهاية الربع.
    if (_page > limit) {
      _page = limit;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager?.hasClients ?? false) _pager!.jumpToPage(limit - first);
      });
    }
    // الآيات برا الورد، أو في الأرباع اللي لسه متفتحتش، بتظهر باهتة.
    bool inRange(int s, int a) => _cmp(s, a, s1, a1) >= 0 && _cmp(s, a, es, ea) <= 0;
    return Listener(
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerUp: _onPointer,
      onPointerCancel: _onPointer,
      key: _kPage,
      child: Directionality(
        // المصحف بيتقلّب من اليمين للشمال حتى لو التطبيق إنجليزي.
        textDirection: TextDirection.rtl,
        child: PageView.builder(
          controller: _pager,
          itemCount: limit - first + 1,
          onPageChanged: (i) {
            setState(() => _page = first + i);
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
            highlight: _highlight,
            onUseHafs: _useHafs,
            onAyahTap: _ayahMenu,
          ),
        ),
      ),
    );
  }

  /// بيوصل لربع حتى لو لسه مش متبني في القايمة (بيقرّب بالتقدير وبعدين بيظبط).
  void _revealQuarter(int quarter, {required VoidCallback then, int tries = 0}) {
    if (r.personal && _goal == null && (quarter < _winFrom || quarter > _winFrom + 7)) {
      // برا الجزء المعروض: نعرض جزءه الأول وبعدين نروح له.
      if (tries > 6 || !mounted) return;
      setState(() => _winFrom = _windowStart(quarter));
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealQuarter(quarter, then: then, tries: tries + 1));
      return;
    }
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
  /// [line]: مكان الآية في الشاشة (٠ = أول سطر، ٠٫٣ = التلت اللي فوق).
  void _jumpToAyah(_AyahPos pos, {double line = 0}) {
    _revealQuarter(pos.quarter, then: () {
      var top = _viewTop;
      if (top == null || !_scroll.hasClients) return;
      top += _scroll.position.viewportDimension * line;
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
    // التلاوة شغالة (أو مستنية آخر الربع): الربع اللي اتفتح بيتضاف عليها وتكمّل من غير ما تقف.
    if (!finishing && _audio.active) {
      final q = _pages ? _pageQuran : _textQuran;
      if (q != null) unawaited(_audio.extend(_quarterAyahs(q, r.fromQuarter + _read), title: _ayahTitle));
    }
    if (!finishing && _auto.active) {
      final q = _pages ? _pageQuran : _textQuran;
      if (q != null) _auto.extend(_withWords(_quarterAyahs(q, r.fromQuarter + _read)));
    }
    if (finishing) {
      if (_audio.active) unawaited(_audio.stop());
      if (_auto.active) _auto.stop();
      await ReadPositions.instance.clear(docId: _posDoc, key: _posKey);
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
    // الربع اتقفل تاني، فالتلاوة بتقف عشان متعديهوش.
    if (_audio.active) unawaited(_audio.stop());
    if (_auto.active) _auto.stop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(points < 0 ? t.undoneWithPoints(-points) : t.undone),
    ));
  }

  String _fontName(AppLocalizations t, String f) => switch (f) {
        madinahFont => t.fontMadinah,
        'Amiri Quran' => t.fontAmiriQuran,
        'Scheherazade New' => t.fontScheherazade,
        'Amiri' => t.fontAmiri,
        _ => t.fontNaskh,
      };

  /// تغيير نوع خط النص المتصل من غير ما يروح للإعدادات: كل خط مكتوب بشكله.
  Future<void> _pickFont() async {
    final t = AppLocalizations.of(context);
    final current = Prefs.instance.readerFont;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.chooseFont, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              // التجويد الملون في النص المتصل.
              SwitchListTile(
                secondary: Icon(Icons.palette_outlined, color: AppColors.accent),
                title: Text(t.textTajweed),
                subtitle: Text(t.textTajweedNote, style: const TextStyle(fontSize: 12)),
                value: Prefs.instance.textTajweed,
                onChanged: (v) => Navigator.pop(context, v ? '#tajweed-on' : '#tajweed-off'),
              ),
              if (Prefs.instance.textTajweed)
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: TajweedLegend(text: true)),
              for (final f in Prefs.readerFonts)
                ListTile(
                  selected: f == current,
                  leading: Icon(f == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  title: Text(_fontName(t, f), style: const TextStyle(fontSize: 13)),
                  subtitle: Text('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
                      textDirection: TextDirection.rtl, style: quranTextStyle(f, fontSize: 22, color: AppColors.text)),
                  onTap: () => Navigator.pop(context, f),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    // نفس الآية تفضل قدامك، والقراءة الصامتة/التلاوة بتكمّل.
    final pos = _readingPosition();
    if (pos != null) _storePosition(pos);
    if (picked.startsWith('#tajweed')) {
      await Prefs.instance.setTextTajweed(picked == '#tajweed-on');
    } else {
      await Prefs.instance.setReaderFont(picked);
    }
    if (!mounted) return;
    setState(() {
      _textData = null;
      _textQuran = null;
      _scrolled = false;
      _anchors.paragraphs.clear();
      _paraRate.clear();
      _autoPadTop = 0;
      _autoPadBottom = 0;
    });
    _afterViewReady();
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
    return Listener(
      // أي لمس للشاشة = لسه بيقرا. وطول ما صباعه على الشاشة الحركة التلقائية بتسيبه
      // (من غيرها كانت بتلغي السحب أول ما يبدأ، فمكانش بيعرف يحرّك غير لما يوقف).
      onPointerDown: (_) {
        ReadingTime.instance.activity();
        _touches++;
      },
      onPointerUp: (_) => _pointerUp(),
      onPointerCancel: (_) => _pointerUp(),
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.personal)
              Text(r.groupName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))
            else ...[
              Text(rangeLabel(t, r.fromQuarter, r.toQuarter), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              Text(r.groupName, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ],
        ),
        // زرار الكتاب دايمًا آخر واحد (أقصى الشمال)، فمكانه ثابت بين الصفحات والنص المتصل.
        actions: [
          if (!_following) ...[
            IconButton(key: _kPlay, tooltip: t.listen, onPressed: _startRecitation, icon: const Icon(Icons.play_circle_outline)),
            IconButton(key: _kAuto, tooltip: t.autoRead, onPressed: _startAutoRead, icon: const Icon(Icons.visibility_outlined)),
          ],
          if (!_pages) ...[
            IconButton(tooltip: t.chooseFont, onPressed: _pickFont, icon: const Icon(Icons.font_download_outlined)),
            IconButton(tooltip: t.textSize, onPressed: () => _changeFont(-2), icon: const Icon(Icons.text_decrease)),
            IconButton(tooltip: t.textSize, onPressed: () => _changeFont(2), icon: const Icon(Icons.text_increase)),
          ],
          IconButton(
            key: _kView,
            tooltip: _pages ? t.viewText : t.mushafPagesView,
            onPressed: () => _setView(_pages ? 'text' : 'pages'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
        // القراءة الصامتة شغالة: تنوّر آية، ولا كلمة، ولا من غير.
        bottom: _auto.active
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  key: _kMode,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(value: 'ayah', label: Text(t.autoModeAyah)),
                      ButtonSegment(value: 'word', label: Text(t.autoModeWord)),
                      ButtonSegment(value: 'none', label: Text(t.autoModeNone)),
                      if (!_pages) ButtonSegment(value: 'manual', label: Text(t.autoModeManual)),
                    ],
                    // اليدوي للنص المتصل بس: في الصفحات بيبقى زي "بدون".
                    selected: {_pages && _auto.mode == 'manual' ? 'none' : _auto.mode},
                    onSelectionChanged: (v) => _auto.setMode(v.first),
                  ),
                ),
              )
            : null,
      ),
      body: FutureBuilder<(QuranData, MushafLayout?)>(
        key: ValueKey('$_view|${Prefs.instance.readerFont}|${Prefs.instance.textTajweed}'),
        future: _data,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final (q, layout) = data;
          if (layout != null) return _pagesBody(q, layout);
          _textQuran = q;
          _scrollToCurrent();
          WidgetsBinding.instance.addPostFrameCallback((_) => _updatePageLabel());
          // بنحفظ المكان بعد ما التمرير يقف بثانية.
          return Stack(
            children: [
              NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              _saveTimer?.cancel();
              _saveTimer = Timer(const Duration(milliseconds: 800), _savePosition);
              return false;
            },
            child: NotificationListener<UserScrollNotification>(
            // لو حرّك الشاشة بإيده، الحركة التلقائية بتسيبه شوية.
            onNotification: (n) {
              _userScrolling = n.direction != ScrollDirection.idle;
              _userScrolledAt = DateTime.now();
              return false;
            },
            child: CustomScrollView(
            key: _viewportKey,
            controller: _scroll,
            slivers: [
              // القراءة الصامتة: مسافة فوق وتحت، عشان أول آية وآخر آية يقدروا يوصلوا لمكان القراية.
              SliverToBoxAdapter(child: SizedBox(height: _autoPadTop)),
              // الأرباع اللي بعد الربع الحالي مبتظهرش غير لما يسجّله.
              if (r.personal && _goal == null && _winFrom > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: OutlinedButton(onPressed: () => _shiftWindow(_winFrom - 8, toEnd: true), child: Text(t.personalPrevJuz)),
                  ),
                ),
              for (var i = _listStart(q); i < r.quarterCount && i <= _read && i <= _listEnd(q); i++) ...[
                SliverToBoxAdapter(
                  // سورة الورد الشخصي: من غير عناوين أرباع، بس المفتاح فاضل عشان نوصل للآية.
                  child: _goal != null
                      ? SizedBox(key: _keyFor(r.fromQuarter + i))
                      : _QuarterHeader(
                          key: _keyFor(r.fromQuarter + i),
                          label: rangeLabel(t, r.fromQuarter + i, r.fromQuarter + i),
                          done: !r.personal && i < _read,
                        ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverToBoxAdapter(child: _QuarterText(data: q, quarter: r.fromQuarter + i, fontSize: _fontSize, anchors: _anchors, onAyahTap: _ayahMenu, highlight: _highlight, onlySurah: _goal, layout: MushafLayout.cached)),
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
                if (i == _read && i < r.quarterCount - 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Text(t.nextQuarterLocked, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                  ),
              ],
              if (r.personal && _goal == null && _winFrom + 8 <= 240)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: FilledButton.tonal(onPressed: () => _shiftWindow(_winFrom + 8), child: Text(t.personalNextJuz)),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
              SliverToBoxAdapter(child: SizedBox(height: _autoPadBottom)),
            ],
          ),
            ),
          ),
              // رقم صفحة مصحف المدينة للي ظاهر على الشاشة (صفحة أو صفحتين).
              if (_pageLabel != null)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(_pageLabel!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  ),
                ),
            ],
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
              // في وضع الصفحات زرار تسجيل الربع بيظهر في صفحة نهاية الربع بس.
              if (_pages && _read < r.quarterCount && _page < _limitPage)
                Padding(
                  key: _kMark,
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(t.readToQuarterEnd, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              if (_pages && _read < r.quarterCount && _page >= _limitPage)
                Padding(
                  key: _kMark,
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: FilledButton(
                    onPressed: _busy ? null : _markQuarter,
                    child: Text(_read == r.quarterCount - 1
                        ? (r.isPortion ? t.finishPortionExtra : t.finishedPortion)
                        : '${t.markQuarterDone} · ${rangeLabel(t, r.fromQuarter + _read, r.fromQuarter + _read)}'),
                  ),
                ),
              // شريط التلاوة تحت زرار "خلصت الربع" ومنفصل عنه، عشان ميتداسش عليه بالغلط.
              if (_auto.active)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4, bottom: 8),
                  child: AutoReadBar(speedKey: _kSpeed),
                ),
              if (_audio.active)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4, bottom: 8),
                  child: RecitationBar(
                    ayahs: () => _recitationAyahs(from: _audio.current),
                    onRestart: _startRecitation,
                    reciterKey: _kReciter,
                    downloadKey: _kDownload,
                  ),
                ),
              if (!r.personal)
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
                key: _kUndo,
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
  const _QuarterText({
    required this.data,
    required this.quarter,
    required this.fontSize,
    required this.anchors,
    required this.onAyahTap,
    this.highlight,
    this.onlySurah,
    this.layout,
  });

  /// سورة من الورد الشخصي: آياتها بس من الربع.
  final int? onlySurah;

  /// توزيع صفحات مصحف المدينة: علامة "صفحة N" قبل أول آية بتبدأ في صفحة جديدة.
  final MushafLayout? layout;

  /// اللي بيتنوّر (آية أو كلمة) في التلاوة أو القراءة التلقائية.
  final ReadHighlight? highlight;

  final void Function(int surah, int ayah) onAyahTap;

  final QuranData data;
  final int quarter;
  final double fontSize;
  final _Anchors anchors;

  static const _digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  String _arabicNumber(int n) => n.toString().split('').map((d) => _digits[int.parse(d)]).join();

  @override
  Widget build(BuildContext context) {
    final ayahs = [for (final a in data.ayahsOfQuarter(quarter)) if (onlySurah == null || a.surah == onlySurah) a];
    final quranStyle = quranTextStyle(Prefs.instance.textFont, fontSize: fontSize, color: AppColors.text);
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
      final starts0 = [...starts];
      // الضغط على أي مكان في الآية بيفتح تفسيرها.
      blocks.add(GestureDetector(
        onTapUp: (d) {
          final rp = para.key.currentContext?.findRenderObject();
          if (rp is! RenderParagraph) return;
          final pos = rp.getPositionForOffset(rp.globalToLocal(d.globalPosition)).offset;
          _AyahStart? hit;
          for (final a in starts0) {
            if (a.offset <= pos) hit = a;
          }
          if (hit != null) onAyahTap(hit.pos.surah, hit.pos.ayah);
        },
        child: Text.rich(TextSpan(children: spans), key: para.key, textAlign: TextAlign.justify, textDirection: TextDirection.rtl),
      ));
      spans = [];
      starts = [];
      length = 0;
    }

    // الصفحة اللي قبل أول آية هنا، عشان العلامة متتكررش في أول كل ربع.
    final pages = layout;
    int? prevPage;
    if (pages != null && ayahs.isNotEmpty) {
      final f = ayahs.first;
      if (f.number > 1) {
        prevPage = pages.pageOf(f.surah, f.number - 1);
      } else if (f.surah > 1) {
        prevPage = pages.pageOf(f.surah - 1, data.ayahCount(f.surah - 1));
      }
    }
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    for (final a in ayahs) {
      if (pages != null) {
        final pg = pages.pageOf(a.surah, a.number);
        if (pg != prevPage) {
          flush();
          blocks.add(_PageMark(label: AppLocalizations.of(context).pageLabel(ar ? arabicDigits(pg) : '$pg')));
        }
        prevPage = pg;
      }
      if (a.number == 1) {
        flush();
        blocks.add(_SurahTitle(name: data.surahNamesAr[a.surah - 1], fontSize: fontSize));
        if (a.surah != 1 && a.surah != 9) {
          blocks.add(Text(data.basmala, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: quranStyle));
        }
      }
      starts.add(_AyahStart(_AyahPos(quarter, a.surah, a.number), length));
      final text = '${a.text} ';
      final h = highlight;
      final lit = quranStyle.copyWith(backgroundColor: readHighlightColor);
      final tj = data.tajweedOf(a.surah, a.number);
      // جزء من الآية بستايل معيّن، ولو التجويد شغال بيتقسم بألوان الأحكام.
      void add(int from, int to, TextStyle st) {
        if (to <= from) return;
        if (tj == null || tj.isEmpty) {
          spans.add(TextSpan(text: text.substring(from, to), style: st));
          return;
        }
        var i = from;
        for (var r = 0; r + 2 < tj.length; r += 3) {
          final s0 = tj[r + 1].clamp(from, to), e0 = tj[r + 2].clamp(from, to);
          if (e0 <= i) continue;
          if (s0 >= to) break;
          if (s0 > i) spans.add(TextSpan(text: text.substring(i, s0), style: st));
          final st0 = s0 > i ? s0 : i;
          spans.add(TextSpan(text: text.substring(st0, e0), style: st.copyWith(color: tajweedColor(tj[r]))));
          i = e0;
        }
        if (i < to) spans.add(TextSpan(text: text.substring(i, to), style: st));
      }

      if (h == null || !h.isAyah(a.surah, a.number)) {
        add(0, text.length, quranStyle);
      } else if (h.word == null) {
        add(0, text.length, lit);
      } else {
        // كلمة واحدة بس منوّرة.
        final ws = ayahWordStarts(a.text);
        final k = h.word!.clamp(0, ws.isEmpty ? 0 : ws.length - 1);
        final from = ws.isEmpty ? 0 : ws[k];
        var to = k + 1 < ws.length ? ws[k + 1] - 1 : a.text.length;
        if (to < from) to = from;
        add(0, from, quranStyle);
        add(from, to, lit);
        add(to, text.length, quranStyle);
      }
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

/// أرقام عربي (٠١٢…).
String arabicDigits(int n) => n.toString().split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();

/// علامة بداية صفحة مصحف المدينة جوه النص المتصل.
class _PageMark extends StatelessWidget {
  const _PageMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.paperLine)),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.paperLabel)),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: AppColors.paperLine)),
        ],
      ),
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
