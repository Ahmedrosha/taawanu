import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_colors.dart';
import 'prefs.dart';

/// خطوط صفحات مجمع الملك فهد (QPC V2، أو V4 الملونة بالتجويد): خط لكل صفحة من الـ٦٠٤.
/// الاتنين بنفس الأكواد، فالفرق بس في ملف الخط. خطوط التجويد من Quran Foundation.
/// كل خط بيتنزل أول مرة الصفحة تتفتح (حوالي ٢٠٠–٣٠٠ كيلو) ويتحفظ على الموبايل،
/// أو المستخدم ينزّلهم كلهم مرة واحدة من الإعدادات.
class MushafFonts extends ChangeNotifier {
  MushafFonts._();

  static final MushafFonts instance = MushafFonts._();

  static const _baseUrl = 'https://taawanu.app/mushaf/qpc2';
  static const _tajweedUrl = 'https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf';
  static const basmalaFamily = 'QPC2_BSML';

  /// التجويد الملون مختار من الإعدادات.
  static bool get tajweed => Prefs.instance.pageStyle == 'tajweed';

  /// رمز البسملة في خط البسملة بتاع المجمع.
  static const basmalaGlyphs = 'ﭑﭒﭓ';

  /// في الوضع الليلي خطوط التجويد بتستخدم ألوانها الفاتحة (لوحة الألوان التانية في الخط).
  static String familyFor(int page) =>
      '${tajweed ? (AppColors.isDark ? 'QPC4D' : 'QPC4') : 'QPC2'}_p${page.toString().padLeft(3, '0')}';
  static String _fileFor(int page) => 'p${page.toString().padLeft(3, '0')}.ttf';

  final _loaded = <String>{};
  final _pending = <String, Future<bool>>{};
  final _dirs = <bool, Directory>{};

  bool isReady(int page) => _loaded.contains(familyFor(page)) && _loaded.contains(basmalaFamily);

  /// فولدر خطوط الصفحات (كل نوع في فولدر). خط البسملة دايمًا في فولدر V2.
  Future<Directory> _folder([bool? tj]) async {
    final t = tj ?? tajweed;
    final d = _dirs[t];
    if (d != null) return d;
    final base = await getApplicationSupportDirectory();
    return _dirs[t] = await Directory('${base.path}/${t ? 'mushaf_qpc4' : 'mushaf_qpc2'}').create(recursive: true);
  }

  /// بيجهّز خط الصفحة (ومعاه خط البسملة). بيرجع false لو مفيش نت والخط مش متحمّل قبل كده.
  Future<bool> ensurePage(int page) async {
    final results = await Future.wait([
      _ensure(basmalaFamily, 'bsml.ttf'),
      _ensure(familyFor(page), _fileFor(page)),
    ]);
    return results.every((ok) => ok);
  }

  /// بيحمّل الصفحات اللي جنب الصفحة الحالية في الخلفية.
  void prefetch(int page, {int around = 2}) {
    for (var p = page - around; p <= page + around; p++) {
      if (p >= 1 && p <= 604 && p != page) _ensure(familyFor(p), _fileFor(p));
    }
  }

  Future<bool> _ensure(String family, String file) {
    if (_loaded.contains(family)) return Future.value(true);
    return _pending.putIfAbsent(family, () async {
      try {
        var bytes = await _bytes(file);
        if (family.startsWith('QPC4D')) bytes = darkPalette(bytes);
        final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        _loaded.add(family);
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('mushaf font $file failed: $e');
        return false;
      } finally {
        _pending.remove(family);
      }
    });
  }

  /// نسخة من الخط بتستخدم لوحة الألوان التانية (المعمولة للخلفية الغامقة) كأنها الأساسية:
  /// في جدول CPAL، أول لوحة بتشاور على نفس ألوان التانية. لو مفيش لوحة تانية الخط بيفضل زي ما هو.
  static Uint8List darkPalette(Uint8List src) {
    final b = Uint8List.fromList(src);
    final d = ByteData.sublistView(b);
    if (b.length < 12) return src;
    final numTables = d.getUint16(4);
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      if (rec + 16 > b.length) break;
      final tag = String.fromCharCodes(b.sublist(rec, rec + 4));
      if (tag != 'CPAL') continue;
      final off = d.getUint32(rec + 8);
      if (off + 14 > b.length) return src;
      final numPalettes = d.getUint16(off + 4);
      if (numPalettes < 2) return src;
      // colorRecordIndices بتبدأ بعد الهيدر (١٢ بايت).
      d.setUint16(off + 12, d.getUint16(off + 14));
      return b;
    }
    return src;
  }

  /// من الموبايل لو موجود، وإلا من النت (وبيتحفظ).
  Future<Uint8List> _bytes(String file) async {
    final tj = tajweed && file != 'bsml.ttf';
    final f = File('${(await _folder(tj)).path}/$file');
    if (await f.exists() && await f.length() > 1000) return f.readAsBytes();
    final bytes = await _download(file, tj);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    return bytes;
  }

  Future<Uint8List> _download(String file, bool tj) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    // خطوط التجويد على Quran Foundation باسم من غير أصفار (p1.ttf).
    final url = tj ? '$_tajweedUrl/p${int.parse(file.substring(1, file.length - 4))}.ttf' : '$_baseUrl/$file';
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final b = BytesBuilder(copy: false);
      await for (final chunk in res) {
        b.add(chunk);
      }
      return b.takeBytes();
    } finally {
      client.close();
    }
  }

  // ---------- تحميل كل الصفحات من الإعدادات ----------

  /// التقدّم من ٠ لـ١ وقت التحميل، وnull لما مفيش تحميل شغال.
  final progress = ValueNotifier<double?>(null);
  bool _cancel = false;

  /// عدد الصفحات المتحمّلة على الموبايل.
  Future<int> downloadedCount() async {
    final dir = await _folder();
    var n = 0;
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.last;
      if (name.startsWith('p') && name.endsWith('.ttf')) n++;
    }
    return n;
  }

  /// بيحمّل كل الصفحات (٤ في نفس الوقت). بيرجع true لو كله اتحمّل.
  Future<bool> downloadAll() async {
    if (progress.value != null) return false;
    _cancel = false;
    progress.value = 0;
    final dir = await _folder();
    final missing = <int>[
      for (var p = 1; p <= 604; p++)
        if (!File('${dir.path}/${_fileFor(p)}').existsSync()) p,
    ];
    var done = 604 - missing.length;
    var failed = false;
    Future<void> worker() async {
      while (missing.isNotEmpty && !_cancel) {
        final p = missing.removeLast();
        try {
          await _bytes(_fileFor(p));
        } catch (_) {
          failed = true;
        }
        done++;
        progress.value = done / 604;
      }
    }

    try {
      await _bytes('bsml.ttf');
      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    } catch (_) {
      failed = true;
    }
    progress.value = null;
    notifyListeners();
    return !failed && !_cancel;
  }

  void cancelDownload() => _cancel = true;

  /// بيمسح الخطوط المتحمّلة (الصفحات المفتوحة دلوقتي بتفضل شغالة لحد ما التطبيق يتقفل).
  Future<void> deleteAll() async {
    final tj = tajweed;
    final dir = await _folder(tj);
    if (await dir.exists()) await dir.delete(recursive: true);
    _dirs.remove(tj);
    notifyListeners();
  }
}
