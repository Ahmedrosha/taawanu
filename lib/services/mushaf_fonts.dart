import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// خطوط صفحات مجمع الملك فهد (QPC V2): خط لكل صفحة من الـ٦٠٤.
/// كل خط بيتنزل أول مرة الصفحة تتفتح (حوالي ٢٠٠–٣٠٠ كيلو) ويتحفظ على الموبايل،
/// أو المستخدم ينزّلهم كلهم مرة واحدة من الإعدادات.
class MushafFonts extends ChangeNotifier {
  MushafFonts._();

  static final MushafFonts instance = MushafFonts._();

  static const _baseUrl = 'https://taawanu.app/mushaf/qpc2';
  static const basmalaFamily = 'QPC2_BSML';

  /// رمز البسملة في خط البسملة بتاع المجمع.
  static const basmalaGlyphs = 'ﭑﭒﭓ';

  static String familyFor(int page) => 'QPC2_p${page.toString().padLeft(3, '0')}';
  static String _fileFor(int page) => 'p${page.toString().padLeft(3, '0')}.ttf';

  final _loaded = <String>{};
  final _pending = <String, Future<bool>>{};
  Directory? _dir;

  bool isReady(int page) => _loaded.contains(familyFor(page)) && _loaded.contains(basmalaFamily);

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    return _dir = await Directory('${base.path}/mushaf_qpc2').create(recursive: true);
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
        final bytes = await _bytes(file);
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

  /// من الموبايل لو موجود، وإلا من النت (وبيتحفظ).
  Future<Uint8List> _bytes(String file) async {
    final f = File('${(await _folder()).path}/$file');
    if (await f.exists() && await f.length() > 1000) return f.readAsBytes();
    final bytes = await _download(file);
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    return bytes;
  }

  Future<Uint8List> _download(String file) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('$_baseUrl/$file'));
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
    final dir = await _folder();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
    notifyListeners();
  }
}
