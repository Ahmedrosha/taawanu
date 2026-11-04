import 'dart:async';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// القراءة التلقائية من غير صوت: الهايلايت بيمشي آية آية، ومدة كل آية على قد عدد كلماتها.
/// بتتصرف زي التلاوة: بتقف آخر الربع لحد ما يتسجّل، وبعدها بتكمّل.
class AutoReader extends ChangeNotifier {
  AutoReader._();

  static final AutoReader instance = AutoReader._();

  /// السرعات المتاحة. ×١ = [wordsPerMinute] كلمة في الدقيقة.
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0];
  static const wordsPerMinute = 60.0;

  /// كل عنصر: (سورة، آية، عدد الكلمات).
  List<(int, int, int)> _items = const [];
  int _index = 0;
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

  /// الوقت الباقي للآية الحالية.
  Duration? get remaining {
    if (!_active || _waiting) return null;
    final left = _playing ? _left - _clock.elapsed : _left;
    return left.isNegative ? Duration.zero : left;
  }

  (int, int)? get current {
    if (!_active || _index >= _items.length) return null;
    final (s, a, _) = _items[_index];
    return (s, a);
  }

  Duration _durationOf(int words) {
    final ms = words / (wordsPerMinute * speed) * 60000;
    // أقل مدة للآية القصيرة: ثانية ونص عادي، وبتقل مع السرعات العالية.
    final min = (1500 / speed).clamp(600, 1500);
    return Duration(milliseconds: ms.clamp(min, 120000).round());
  }

  void play(List<(int, int, int)> ayahs) {
    if (ayahs.isEmpty) return;
    _items = ayahs;
    _index = 0;
    _active = true;
    _waiting = false;
    _start(_durationOf(ayahs.first.$3));
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
      _start(_durationOf(_items[_index].$3));
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
    if (_index + 1 < _items.length) {
      _index++;
      _start(_durationOf(_items[_index].$3));
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
    _start(_left > Duration.zero ? _left : _durationOf(_items[_index].$3));
    notifyListeners();
  }

  void next() {
    if (!_active || _index + 1 >= _items.length) return;
    _index++;
    _waiting = false;
    if (_playing) {
      _start(_durationOf(_items[_index].$3));
    } else {
      _left = _durationOf(_items[_index].$3);
    }
    notifyListeners();
  }

  void previous() {
    if (!_active || _index == 0) return;
    _index--;
    _waiting = false;
    if (_playing) {
      _start(_durationOf(_items[_index].$3));
    } else {
      _left = _durationOf(_items[_index].$3);
    }
    notifyListeners();
  }

  /// السرعة الجاية (+١) أو اللي قبلها (-١). بتتطبّق من الآية الجاية.
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
    notifyListeners();
  }
}
