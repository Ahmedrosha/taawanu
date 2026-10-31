import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// كلمة في سطر من صفحة المصحف.
class MushafWord {
  const MushafWord(this.surah, this.ayah, this.hafs, this.qpc);

  final int surah;
  final int ayah;

  /// نص الكلمة بخط حفص (مجمع الملك فهد)، ومعاها رقم الآية لو هي آخر كلمة.
  final String hafs;

  /// رمز الكلمة في خط الصفحة بتاع المجمع (QPC V2).
  final String qpc;
}

enum MushafLineType { surahHeader, basmala, text }

class MushafLine {
  const MushafLine.header(this.surah)
      : type = MushafLineType.surahHeader,
        words = const [];
  const MushafLine.basmala()
      : type = MushafLineType.basmala,
        surah = 0,
        words = const [];
  const MushafLine.text(this.words)
      : type = MushafLineType.text,
        surah = 0;

  final MushafLineType type;
  final int surah;
  final List<MushafWord> words;
}

/// توزيع صفحات وسطور مصحف المدينة: ٦٠٤ صفحة، ١٥ سطر (من assets/mushaf/pages.json).
class MushafLayout {
  MushafLayout._(this.pages, this._firstAyah, this._startPage, this._endPage);

  static const pageCount = 604;

  /// الصفحات من ١: pages[0] = صفحة ١.
  final List<List<MushafLine>> pages;

  /// أول آية بتبدأ في كل صفحة (أو الآية المكمّلة لو مفيش آية بتبدأ فيها).
  final List<(int, int)> _firstAyah;

  /// الصفحة اللي بتبدأ فيها كل آية: المفتاح سورة×١٠٠٠+آية.
  final Map<int, int> _startPage;

  /// الصفحة اللي بتخلص فيها كل آية.
  final Map<int, int> _endPage;

  static MushafLayout? _cached;
  static Future<MushafLayout>? _loading;

  static Future<MushafLayout> load() => _loading ??= () async {
        final raw = await rootBundle.loadString('assets/mushaf/pages.json');
        return _cached = await compute(_parse, raw);
      }();

  static MushafLayout? get cached => _cached;

  static MushafLayout _parse(String raw) {
    final d = jsonDecode(raw) as Map<String, dynamic>;
    final pages = <List<MushafLine>>[];
    final first = <(int, int)>[];
    final start = <int, int>{};
    final end = <int, int>{};
    for (final p in d['pages'] as List) {
      final number = pages.length + 1;
      final lines = <MushafLine>[];
      (int, int)? continuing;
      (int, int)? starting;
      for (final l in p as List) {
        final kind = l[0] as String;
        if (kind == 'h') {
          lines.add(MushafLine.header(l[1] as int));
        } else if (kind == 'b') {
          lines.add(const MushafLine.basmala());
        } else {
          final words = <MushafWord>[];
          for (final w in l[1] as List) {
            final word = MushafWord(w[0] as int, w[1] as int, w[2] as String, w[3] as String);
            words.add(word);
            continuing ??= (word.surah, word.ayah);
            final key = word.surah * 1000 + word.ayah;
            end[key] = number;
            if (!start.containsKey(key)) {
              start[key] = number;
              starting ??= (word.surah, word.ayah);
            }
          }
          lines.add(MushafLine.text(words));
        }
      }
      pages.add(lines);
      first.add(starting ?? continuing ?? (1, 1));
    }
    return MushafLayout._(pages, first, start, end);
  }

  List<MushafLine> page(int number) => pages[number - 1];

  (int, int) firstAyahOf(int page) => _firstAyah[page - 1];

  /// الصفحة اللي فيها بداية الآية دي.
  int pageOf(int surah, int ayah) => _startPage[surah * 1000 + ayah] ?? 1;

  /// الصفحة اللي فيها آخر الآية دي.
  int endPageOf(int surah, int ayah) => _endPage[surah * 1000 + ayah] ?? pageCount;

  /// السور اللي ظاهرة في الصفحة (لعنوان أعلى الصفحة).
  List<int> surahsOn(int page) {
    final out = <int>[];
    for (final l in pages[page - 1]) {
      final s = l.type == MushafLineType.surahHeader
          ? l.surah
          : (l.words.isNotEmpty ? l.words.first.surah : 0);
      if (s > 0 && !out.contains(s)) out.add(s);
    }
    return out;
  }
}
