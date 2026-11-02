import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// تفسير متاح في التطبيق.
class TafsirInfo {
  const TafsirInfo({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.sourceAr,
    required this.sourceEn,
    this.bundled = false,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String sourceAr;
  final String sourceEn;

  /// جوه التطبيق (من غير نت). الباقي بيتحمّل سورة سورة أول مرة.
  final bool bundled;
}

/// تفسير آية: النص (بعلامات <q> <b> <r> <h>)، والآيات اللي بيغطيها لو كذا آية مع بعض.
class TafsirEntry {
  const TafsirEntry(this.text, this.fromAyah, this.toAyah);

  final String text;
  final int fromAyah;
  final int toAyah;

  bool get isGroup => fromAyah != toAyah;
}

class TafsirRepository {
  TafsirRepository._();
  static final TafsirRepository instance = TafsirRepository._();

  static const _baseUrl = 'https://taawanu.app/tafsir';

  static const tafsirs = [
    TafsirInfo(
      id: 'muyassar',
      nameAr: 'الميسر',
      nameEn: 'Al-Muyassar',
      sourceAr: 'التفسير الميسر — مجمع الملك فهد لطباعة المصحف الشريف (عن موقع تنزيل)',
      sourceEn: 'Al-Muyassar — King Fahd Glorious Quran Printing Complex (via Tanzil)',
      bundled: true,
    ),
    TafsirInfo(
      id: 'saadi',
      nameAr: 'السعدي',
      nameEn: 'As-Saadi',
      sourceAr: 'تيسير الكريم الرحمن — عبد الرحمن السعدي (عن مكتبة QUL)',
      sourceEn: "Taysir al-Karim ar-Rahman — Abd ar-Rahman as-Sa'di (via QUL)",
    ),
    TafsirInfo(
      id: 'ibnkathir',
      nameAr: 'ابن كثير',
      nameEn: 'Ibn Kathir',
      sourceAr: 'تفسير القرآن العظيم — ابن كثير (عن مكتبة QUL، من غير حواشي فروق النسخ)',
      sourceEn: 'Tafsir al-Quran al-Azim — Ibn Kathir (via QUL, manuscript footnotes omitted)',
    ),
  ];

  static TafsirInfo info(String id) => tafsirs.firstWhere((t) => t.id == id, orElse: () => tafsirs.first);

  Future<List<List<String>>>? _muyassar;
  final _surahs = <String, Future<List<Object?>>>{};

  Future<List<List<String>>> _loadMuyassar() => _muyassar ??= () async {
        final raw = await rootBundle.loadString('assets/tafsir/muyassar.json');
        return compute(_parseBundled, raw);
      }();

  static List<List<String>> _parseBundled(String raw) {
    final d = jsonDecode(raw) as Map<String, dynamic>;
    return [for (final s in d['surahs'] as List) List<String>.from(s as List)];
  }

  static List<Object?> _parseSurah(String raw) => List<Object?>.from((jsonDecode(raw) as Map<String, dynamic>)['a'] as List);

  /// سورة من تفسير بيتحمّل: من الموبايل لو اتحمّلت قبل كده، وإلا من الموقع (وبتتحفظ).
  Future<List<Object?>> _loadSurah(String id, int surah) {
    final key = '$id/$surah';
    return _surahs.putIfAbsent(key, () async {
      try {
        final dir = Directory('${(await getApplicationSupportDirectory()).path}/tafsir/$id');
        final file = File('${dir.path}/$surah.json');
        String raw;
        if (await file.exists()) {
          raw = await file.readAsString();
        } else {
          raw = await _download('$_baseUrl/$id/$surah.json');
          await dir.create(recursive: true);
          await file.writeAsString(raw, flush: true);
        }
        return compute(_parseSurah, raw);
      } catch (e) {
        _surahs.remove(key);
        rethrow;
      }
    });
  }

  Future<String> _download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// تفسير آية. بيرمي خطأ لو التفسير محتاج نت ومفيش. null لو مفيش تفسير للآية.
  Future<TafsirEntry?> ayah(String id, int surah, int ayah) async {
    if (info(id).bundled) {
      final data = await _loadMuyassar();
      if (surah < 1 || surah > data.length || ayah < 1 || ayah > data[surah - 1].length) return null;
      return TafsirEntry(data[surah - 1][ayah - 1], ayah, ayah);
    }
    final items = await _loadSurah(id, surah);
    if (ayah < 1 || ayah > items.length) return null;
    // الآية ممكن تكون جزء من مجموعة ليها تفسير واحد (رقم = أول آية في المجموعة)،
    // أو من غير تفسير منفصل (null = تفسيرها مع اللي قبلها).
    var head = ayah;
    while (head >= 1) {
      final v = items[head - 1];
      if (v is String) break;
      if (v is num) {
        head = v.toInt();
        break;
      }
      head--;
    }
    if (head < 1 || items[head - 1] is! String) return null;
    var to = head;
    for (var a = head + 1; a <= items.length; a++) {
      final v = items[a - 1];
      if ((v is num && v.toInt() == head) || v == null) {
        to = a;
      } else {
        break;
      }
    }
    if (to < ayah) to = ayah;
    return TafsirEntry(items[head - 1] as String, head, to);
  }
}
