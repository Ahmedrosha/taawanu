import 'dart:async';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// القراءة التلقائية من غير صوت: المكان بيمشي كلمة كلمة بسرعة ثابتة (×١ = كلمة في الثانية).
/// العرض بيختار يبيّن إيه: الآية كلها، أو الكلمة، أو ولا حاجة ([AutoReadMode]).
/// بتتصرف زي التلاوة: بتقف آخر الربع لحد ما يتسجّل، وبعدها بتكمّل.
class AutoReader extends ChangeNotifier {
  AutoReader._();

  static final AutoReader instance = AutoReader._();

  /// السرعات المتاحة. ×١ = [wordsPerMinute] كلمة في الدقيقة.
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0];
  static const wordsPerMinute = 60.0;

  /// كل عنصر: (سورة، آية، عدد الكلمات).
  List<(int, int, int)> _items = const [];
  int _index = 0, _word = 0;
  bool _active = false, _playing = false, _waiting = false;
  Timer? _timer;
  final _clock = Stopwatch();
  Duration _left = Duration.zero;

  bool get active => _active;
  bool get playing => _playing;

  /// وصلت آخر الربع ومستنية تسجيله.
  bool get waiting => _waiting;

  double get speed {
    final s = Prefs.instance.autoReadSpeed;
    return speeds.contains(s) ? s : 1.0;
  }

  /// آية / كلمة / بدون تنوير.
  String get mode {
    final m = Prefs.instance.autoReadMode;
    return const ['ayah', 'word', 'none'].contains(m) ? m : 'ayah';
  }

  Future<void> setMode(String m) async {
    await Prefs.instance.setAutoReadMode(m);
    notifyListeners();
  }

  (int, int)? get current {
    if (!_active || _index >= _items.length) return null;
    final (s, a, _) = _items[_index];
    return (s, a);
  }

  /// رقم الكلمة الحالية جوه الآية (من ٠).
  int? get word => _active && _index < _items.length ? _word : null;

  /// عدد كلمات الآية الحالية.
  int get wordsInAyah => _active && _index < _items.length ? _items[_index].$3 : 0;

  /// مدة الكلمة الواحدة بالسرعة الحالية.
  Duration get wordDuration => Duration(milliseconds: (60000 / (wordsPerMinute * speed)).round());

  /// الآيات اللي بتتقري: (سورة، آية، عدد الكلمات).
  List<(int, int, int)> get items => _items;

  /// نفس الآيات بعدد كلمات تاني (لما يبدّل بين الصفحات والنص): بتكمّل من نفس المكان في الآية.
  void remap(List<(int, int, int)> ayahs) {
    if (!_active || ayahs.length != _items.length || ayahs.isEmpty) return;
    final old = _items[_index].$3;
    final now = ayahs[_index].$3;
    _items = ayahs;
    _word = old <= 1 ? 0 : ((_word / (old - 1)) * (now - 1)).round().clamp(0, now - 1);
    notifyListeners();
  }

  void play(List<(int, int, int)> ayahs) {
    if (ayahs.isEmpty) return;
    _items = ayahs;
    _index = 0;
    _word = 0;
    _active = true;
    _waiting = false;
    _start(wordDuration);
    notifyListeners();
  }

  /// ربع جديد اتفتح: بيتضاف، ولو كانت مستنية بتكمّل منه.
  void extend(List<(int, int, int)> ayahs) {
    if (!_active || ayahs.isEmpty) return;
    final firstNew = _items.length;
    _items = [..._items, ...ayahs];
    if (_waiting) {
      _waiting = false;
      _index = firstNew;
      _word = 0;
      _start(wordDuration);
    }
    notifyListeners();
  }

  void _start(Duration d) {
    _timer?.cancel();
    _left = d;
    _clock
      ..reset()
      ..start();
    _playing = true;
    _timer = Timer(d, _advance);
  }

  void _advance() {
    final words = _items[_index].$3;
    if (_word + 1 < words) {
      _word++;
      _start(wordDuration);
    } else if (_index + 1 < _items.length) {
      _index++;
      _word = 0;
      _start(wordDuration);
    } else {
      // آخر الآيات المفتوحة: نستنى التسجيل.
      _timer?.cancel();
      _clock.stop();
      _playing = false;
      _waiting = true;
    }
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _timer?.cancel();
    _clock.stop();
    _left -= _clock.elapsed;
    _playing = false;
    notifyListeners();
  }

  void resume() {
    if (!_active || _playing || _waiting) return;
    _start(_left > Duration.zero ? _left : wordDuration);
    notifyListeners();
  }

  void _jump(int index) {
    _index = index;
    _word = 0;
    _waiting = false;
    if (_playing) {
      _start(wordDuration);
    } else {
      _left = wordDuration;
    }
    notifyListeners();
  }

  void next() {
    if (_active && _index + 1 < _items.length) _jump(_index + 1);
  }

  void previous() {
    if (_active && _index > 0) _jump(_index - 1);
  }

  /// السرعة الجاية (+١) أو اللي قبلها (-١). بتتطبّق من الكلمة الجاية.
  Future<void> changeSpeed(int step) async {
    final i = (speeds.indexOf(speed) + step).clamp(0, speeds.length - 1);
    await Prefs.instance.setAutoReadSpeed(speeds[i]);
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _clock.stop();
    _active = false;
    _playing = false;
    _waiting = false;
    _items = const [];
    _index = 0;
    _word = 0;
    notifyListeners();
  }
}

/// أماكن بداية الكلمات جوه نص الآية: الكلمة = جزء بين مسافتين فيه حرف عربي
/// (علامات الوقف والأرقام اللي لوحدها بتتبع الكلمة اللي قبلها).
List<int> ayahWordStarts(String text) {
  final out = <int>[];
  var i = 0;
  for (final token in text.split(' ')) {
    if (_letter.hasMatch(token)) out.add(i);
    i += token.length + 1;
  }
  return out;
}

final _letter = RegExp('[ء-غف-يٱ-ۓۺ-ۼ]');
