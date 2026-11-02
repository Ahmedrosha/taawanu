import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'prefs.dart';

/// قارئ: تلاوة آية بآية من EveryAyah.
class Reciter {
  const Reciter(this.id, this.nameAr, this.nameEn, this.folder);

  final String id;
  final String nameAr;
  final String nameEn;

  /// اسم المجلد على everyayah.com/data/
  final String folder;
}

/// تشغيل التلاوة آية آية: الآية الحالية، والتكرار، وتحميل الورد للتشغيل من غير نت.
class RecitationPlayer extends ChangeNotifier {
  RecitationPlayer._() {
    _player.currentIndexStream.listen((_) => notifyListeners());
    _player.playerStateStream.listen((s) {
      // وصلت آخر الربع: بتستنى لحد ما يسجّل الربع، وبعدها القارئ بيكمّل الربع اللي بعده.
      if (s.processingState == ProcessingState.completed && _active && !_waiting) {
        _waiting = true;
        _player.pause();
      }
      notifyListeners();
    });
  }

  static final RecitationPlayer instance = RecitationPlayer._();

  static const _base = 'https://everyayah.com/data';

  static const reciters = [
    Reciter('alafasy', 'مشاري العفاسي', 'Mishary Alafasy', 'Alafasy_128kbps'),
    Reciter('husary', 'محمود خليل الحصري', 'Mahmoud Al-Husary', 'Husary_128kbps'),
    Reciter('minshawi', 'محمد صديق المنشاوي', 'Mohamed Al-Minshawi', 'Minshawy_Murattal_128kbps'),
    Reciter('abdulbasit', 'عبد الباسط عبد الصمد', 'Abdul Basit', 'Abdul_Basit_Murattal_192kbps'),
    Reciter('sudais', 'عبد الرحمن السديس', 'Abdurrahman As-Sudais', 'Abdurrahmaan_As-Sudais_64kbps'),
    Reciter('shuraym', 'سعود الشريم', 'Saud Ash-Shuraym', 'Saood_ash-Shuraym_128kbps'),
    Reciter('muaiqly', 'ماهر المعيقلي', 'Maher Al-Muaiqly', 'MaherAlMuaiqly128kbps'),
  ];

  static Reciter reciterById(String id) => reciters.firstWhere((r) => r.id == id, orElse: () => reciters.first);

  final _player = AudioPlayer();

  /// كل عنصر في قايمة التشغيل: (سورة، آية). الآية ٠ = البسملة قبل أول السورة.
  List<(int, int)> _items = const [];
  bool _active = false;

  Reciter get reciter => reciterById(Prefs.instance.reciterId);

  /// عدد مرات تكرار كل آية (٠ = لحد ما يوقّف).
  int get repeat => Prefs.instance.recitationRepeat;

  bool get active => _active;

  /// التلاوة وصلت آخر الربع ومستنية تسجيله عشان تكمّل.
  bool get waiting => _waiting;
  bool _waiting = false;
  bool get playing => _player.playing;

  /// الآية اللي بتتقري دلوقتي (البسملة بتتحسب على أول آية في السورة).
  (int, int)? get current {
    final i = _player.currentIndex;
    if (!_active || i == null || i >= _items.length) return null;
    final (s, a) = _items[i];
    return (s, a == 0 ? 1 : a);
  }

  String _file(int s, int a) => '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}.mp3';

  Future<Directory> _dir(Reciter r) async =>
      Directory('${(await getApplicationSupportDirectory()).path}/audio/${r.folder}');

  /// بيشغّل الآيات دي بالترتيب (لحد آخر الربع اللي عليه، القارئ هو اللي بيحدد).
  Future<void> play(List<(int, int)> ayahs, {required String Function(int surah, int ayah) title}) async {
    if (ayahs.isEmpty) return;
    final (items, sources) = await _build(ayahs, title);
    _items = items;
    _active = true;
    _waiting = false;
    await _player.setLoopMode(repeat == 0 ? LoopMode.one : LoopMode.off);
    await _player.setAudioSources(sources, initialIndex: 0, initialPosition: Duration.zero);
    notifyListeners();
    unawaited(_player.play());
  }

  /// بيزوّد آيات على قايمة التشغيل من غير ما يقطعها (لما ربع جديد يتفتح).
  /// لو التلاوة كانت واقفة مستنية آخر الربع، بتكمّل من أول الآيات الجديدة.
  Future<void> extend(List<(int, int)> ayahs, {required String Function(int surah, int ayah) title}) async {
    if (!_active || ayahs.isEmpty) return;
    final (items, sources) = await _build(ayahs, title);
    final firstNew = _items.length;
    _items = [..._items, ...items];
    await _player.addAudioSources(sources);
    if (_waiting) {
      _waiting = false;
      await _player.seek(Duration.zero, index: firstNew);
      unawaited(_player.play());
    }
    notifyListeners();
  }

  Future<(List<(int, int)>, List<AudioSource>)> _build(List<(int, int)> ayahs, String Function(int, int) title) async {
    final r = reciter;
    final dir = await _dir(r);
    final times = repeat == 0 ? 1 : repeat;
    final items = <(int, int)>[];
    final sources = <AudioSource>[];
    for (final (s, a) in ayahs) {
      // البسملة قبل أول آية في كل سورة (غير الفاتحة والتوبة).
      final withBasmala = a == 1 && s != 1 && s != 9;
      for (var k = 0; k < times; k++) {
        if (withBasmala && k == 0) {
          items.add((s, 0));
          sources.add(await _source(dir, r, 1, 1, title(s, 1)));
        }
        items.add((s, a));
        sources.add(await _source(dir, r, s, a, title(s, a)));
      }
    }
    return (items, sources);
  }

  Future<AudioSource> _source(Directory dir, Reciter r, int s, int a, String title) async {
    final name = _file(s, a);
    final local = File('${dir.path}/$name');
    if (await local.exists()) return AudioSource.file(local.path);
    return AudioSource.uri(Uri.parse('$_base/${r.folder}/$name'));
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();

  Future<void> stop() async {
    _active = false;
    _waiting = false;
    await _player.stop();
    notifyListeners();
  }

  Future<void> next() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> previous() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  // ---------- تحميل الورد ----------

  final downloadProgress = ValueNotifier<double?>(null);

  /// بيحمّل الآيات دي بصوت القارئ الحالي (والبسملة). بيرجع true لو كله اتحمّل.
  Future<bool> download(List<(int, int)> ayahs) async {
    if (downloadProgress.value != null) return false;
    final r = reciter;
    final dir = await _dir(r);
    await dir.create(recursive: true);
    final files = <(int, int)>{(1, 1), ...ayahs}.toList();
    var done = 0, failed = false;
    downloadProgress.value = 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      for (final (s, a) in files) {
        final f = File('${dir.path}/${_file(s, a)}');
        if (!await f.exists()) {
          try {
            final res = await (await client.getUrl(Uri.parse('$_base/${r.folder}/${_file(s, a)}'))).close();
            if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
            final tmp = File('${f.path}.part');
            await res.pipe(tmp.openWrite());
            await tmp.rename(f.path);
          } catch (e) {
            debugPrint('audio download failed: $e');
            failed = true;
          }
        }
        done++;
        downloadProgress.value = done / files.length;
      }
    } finally {
      client.close();
      downloadProgress.value = null;
    }
    return !failed;
  }

  /// كام آية من دول متحمّلة بصوت القارئ الحالي.
  Future<int> downloadedCount(List<(int, int)> ayahs) async {
    final dir = await _dir(reciter);
    var n = 0;
    for (final (s, a) in ayahs) {
      if (await File('${dir.path}/${_file(s, a)}').exists()) n++;
    }
    return n;
  }
}
