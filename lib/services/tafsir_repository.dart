import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// تفسير متاح في التطبيق.
class TafsirInfo {
  const TafsirInfo({required this.id, required this.nameAr, required this.nameEn, required this.sourceAr, required this.sourceEn});

  final String id;
  final String nameAr;
  final String nameEn;
  final String sourceAr;
  final String sourceEn;
}

/// التفاسير. الميسر جوه التطبيق وشغال من غير نت.
class TafsirRepository {
  TafsirRepository._();
  static final TafsirRepository instance = TafsirRepository._();

  static const tafsirs = [
    TafsirInfo(
      id: 'muyassar',
      nameAr: 'التفسير الميسر',
      nameEn: 'Al-Muyassar',
      sourceAr: 'التفسير الميسر — مجمع الملك فهد لطباعة المصحف الشريف (عن موقع تنزيل)',
      sourceEn: 'Al-Muyassar — King Fahd Glorious Quran Printing Complex (via Tanzil)',
    ),
  ];

  Future<List<List<String>>>? _muyassar;

  Future<List<List<String>>> _loadMuyassar() => _muyassar ??= () async {
        final raw = await rootBundle.loadString('assets/tafsir/muyassar.json');
        return compute(_parse, raw);
      }();

  static List<List<String>> _parse(String raw) {
    final d = jsonDecode(raw) as Map<String, dynamic>;
    return [for (final s in d['surahs'] as List) List<String>.from(s as List)];
  }

  /// تفسير آية. بيرجّع null لو مش موجود.
  Future<String?> ayah(String tafsirId, int surah, int ayah) async {
    final data = await _loadMuyassar();
    if (surah < 1 || surah > data.length) return null;
    final list = data[surah - 1];
    if (ayah < 1 || ayah > list.length) return null;
    return list[ayah - 1];
  }
}
