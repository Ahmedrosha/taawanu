import 'dart:convert';

import 'package:flutter/services.dart';

// الأذكار من حصن المسلم (ملفات assets/adhkar)، والآيات بتتقري من نص المصحف نفسه.

class Dhikr {
  const Dhikr({required this.id, this.text, this.quran, required this.count, this.virtue, this.source});

  final String id;
  final String? text;

  /// آيات من المصحف: (سورة، من آية، لحد آية).
  final (int, int, int)? quran;
  final int count;

  /// فضل الذكر أو متى يُقال.
  final String? virtue;
  final String? source;

  factory Dhikr.fromJson(Map<String, dynamic> j) {
    final q = j['quran'] as List?;
    return Dhikr(
      id: j['id'] as String,
      text: j['text'] as String?,
      quran: q == null ? null : ((q[0] as num).toInt(), (q[1] as num).toInt(), (q[2] as num).toInt()),
      count: (j['count'] as num?)?.toInt() ?? 1,
      virtue: j['virtue'] as String?,
      source: j['source'] as String?,
    );
  }
}

class AdhkarCategory {
  const AdhkarCategory({required this.id, required this.ar, required this.en, required this.items});

  final String id;
  final String ar;
  final String en;
  final List<Dhikr> items;
}

class HisnChapter {
  const HisnChapter({required this.title, required this.texts, required this.footnotes});

  final String title;
  final List<String> texts;
  final List<String> footnotes;
}

class AdhkarRepository {
  AdhkarRepository._();
  static final instance = AdhkarRepository._();

  Future<List<AdhkarCategory>>? _daily;
  Future<List<HisnChapter>>? _hisn;

  Future<List<AdhkarCategory>> daily() => _daily ??= () async {
        final d = jsonDecode(await rootBundle.loadString('assets/adhkar/daily.json')) as Map<String, dynamic>;
        return [
          for (final c in d['categories'] as List)
            AdhkarCategory(
              id: c['id'] as String,
              ar: c['ar'] as String,
              en: c['en'] as String,
              items: [for (final i in c['items'] as List) Dhikr.fromJson(i as Map<String, dynamic>)],
            ),
        ];
      }();

  Future<List<HisnChapter>> hisn() => _hisn ??= () async {
        final d = jsonDecode(await rootBundle.loadString('assets/adhkar/hisn.json')) as Map<String, dynamic>;
        return [
          for (final c in d['chapters'] as List)
            HisnChapter(
              title: c['title'] as String,
              texts: List<String>.from(c['texts'] as List),
              footnotes: List<String>.from(c['footnotes'] as List),
            ),
        ];
      }();
}

/// للبحث: من غير تشكيل، والألف والياء والتاء المربوطة موحّدة.
String normalizeArabic(String s) => s
    .replaceAll(RegExp('[ً-ْٰـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه');
