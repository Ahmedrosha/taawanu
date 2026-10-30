import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';

class Ayah {
  const Ayah({required this.surah, required this.number, required this.text});

  final int surah; // ١–١١٤
  final int number;
  final String text;
}

/// نص المصحف وحدود الأرباع (من ملف assets/quran/quran.json).
class QuranData {
  QuranData._(this.basmala, this.surahNamesAr, this.surahNamesEn, this._quarters, this._surahs);

  final String basmala;
  final List<String> surahNamesAr;
  final List<String> surahNamesEn;
  final List<List<int>> _quarters; // بداية كل ربع: [سورة، آية]
  final List<List<String>> _surahs;

  static QuranData _parse(String raw) {
    final d = jsonDecode(raw) as Map<String, dynamic>;
    return QuranData._(
      d['basmala'] as String,
      List<String>.from(d['surahNamesAr'] as List),
      List<String>.from(d['surahNamesEn'] as List),
      [for (final q in d['quarters'] as List) List<int>.from(q as List)],
      [for (final s in d['surahs'] as List) List<String>.from(s as List)],
    );
  }

  int ayahCount(int surah) => _surahs[surah - 1].length;

  String ayahText(int surah, int ayah) => _surahs[surah - 1][ayah - 1];

  String surahName(int surah, String locale) =>
      locale == 'en' ? surahNamesEn[surah - 1] : surahNamesAr[surah - 1];

  /// أول آية في الربع (١–٢٤٠).
  (int, int) quarterStart(int quarter) => (_quarters[quarter - 1][0], _quarters[quarter - 1][1]);

  /// آخر آية في الربع.
  (int, int) quarterEnd(int quarter) {
    if (quarter >= 240) return (114, ayahCount(114));
    final (s, a) = quarterStart(quarter + 1);
    if (a > 1) return (s, a - 1);
    return (s - 1, ayahCount(s - 1));
  }

  /// كل آيات الربع بالترتيب.
  List<Ayah> ayahsOfQuarter(int quarter) {
    final (s1, a1) = quarterStart(quarter);
    final (s2, a2) = quarterEnd(quarter);
    final out = <Ayah>[];
    for (var s = s1; s <= s2; s++) {
      final from = s == s1 ? a1 : 1;
      final to = s == s2 ? a2 : ayahCount(s);
      for (var a = from; a <= to; a++) {
        out.add(Ayah(surah: s, number: a, text: _surahs[s - 1][a - 1]));
      }
    }
    return out;
  }
}

class QuranRepository {
  QuranRepository._();
  static final QuranRepository instance = QuranRepository._();

  Future<QuranData>? _loading;

  /// بيتحمّل مرة واحدة، وبيتفك في خيط منفصل عشان الواجهة متقفش.
  Future<QuranData> load() => _loading ??= () async {
        final raw = await rootBundle.loadString('assets/quran/quran.json');
        return compute(QuranData._parse, raw);
      }();
}

/// وصف مدى الأرباع: الجزء ٧، الحزب ١٣، الأرباع ٣–٥…
String rangeLabel(AppLocalizations t, int from, int to) {
  final count = to - from + 1;
  if ((from - 1) % 8 == 0 && count % 8 == 0) {
    final a = (from - 1) ~/ 8 + 1;
    final b = to ~/ 8;
    return a == b ? t.juzLabel(a) : t.juzRange(a, b);
  }
  if ((from - 1) % 4 == 0 && count % 4 == 0) {
    final a = (from - 1) ~/ 4 + 1;
    final b = to ~/ 4;
    return a == b ? t.hizbLabel(a) : t.hizbRange(a, b);
  }
  return count == 1 ? t.quarterLabel(from) : t.quarterRange(from, to);
}

/// "من البقرة ١ لحد البقرة ١٤١".
String rangeAyahs(AppLocalizations t, QuranData q, String locale, int from, int to) {
  final (s1, a1) = q.quarterStart(from);
  final (s2, a2) = q.quarterEnd(to);
  String clean(String name) => name.replaceFirst(RegExp(r'^سُوْرَةُ\s*'), '');
  return t.fromTo('${clean(q.surahName(s1, locale))} $a1', '${clean(q.surahName(s2, locale))} $a2');
}
