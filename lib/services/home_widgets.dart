import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../features/adhkar/adhkar_data.dart';
import '../features/prayer/prayer_controller.dart';
import '../features/prayer/prayer_screen.dart' show prayerName;
import '../features/prayer/prayer_times.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/group_models.dart';
import 'prefs.dart';
import 'quran_repository.dart';

/// ويدجتس الشاشة الرئيسية (أندرويد وأيفون): التطبيق بيكتب البيانات جاهزة بالنصوص، والويدجت بيعرضها.
/// أندرويد بيقراها من ملف الإعدادات، والأيفون بتتبعتله وبيحفظها في App Group.
class HomeWidgets {
  HomeWidgets._();
  static final instance = HomeWidgets._();

  static const _channel = MethodChannel('taawanu/widgets');
  static const _prayers = [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha];

  bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  AppLocalizations get _t => lookupAppLocalizations(Prefs.instance.locale);

  final _wards = <String, Map<String, dynamic>>{};
  final _last = <String, String>{};

  Future<void> _save(String key, Map<String, dynamic> data) async {
    final raw = jsonEncode(data);
    if (_last[key] == raw) return;
    _last[key] = raw;
    try {
      await Prefs.instance.setWidgetData(key, raw);
      await _channel.invokeMethod<void>('update', {key: raw});
    } catch (_) {
      // الويدجتس مش أساسية.
    }
  }

  /// عند فتح التطبيق: الصلاة وذكر اليوم.
  Future<void> start() async {
    if (!_supported) return;
    PrayerController.instance.addListener(updatePrayer);
    await updatePrayer();
    await _updateDhikr();
  }

  /// مواقيت ٧ أيام قدام، والويدجت بيتنقل بينها لوحده.
  Future<void> updatePrayer() async {
    if (!_supported) return;
    final t = _t;
    final c = PrayerController.instance;
    final times = <Map<String, dynamic>>[];
    if (c.hasLocation) {
      final now = DateTime.now();
      for (var d = 0; d < 7; d++) {
        final day = c.timesFor(DateTime(now.year, now.month, now.day + d));
        for (final p in _prayers) {
          times.add({'n': prayerName(t, p), 't': day[p].millisecondsSinceEpoch});
        }
      }
    }
    await _save('widget_prayer', {'title': t.widgetNextPrayer, 'empty': t.widgetSetLocation, 'times': times});
  }

  /// ورد المستخدم في مجموعة (بيتنده من الرئيسية كل ما الورد يتغير).
  void setWard(Group g, Assignment? a) {
    if (!_supported) return;
    final t = _t;
    if (a == null || a.closed) {
      _wards.remove(g.id);
    } else {
      _wards[g.id] = {
        'gid': g.id,
        'group': g.name,
        'title': rangeLabel(t, a.fromQuarter, a.toQuarter),
        'read': a.quartersRead,
        'total': a.quarterCount,
        'done': a.isDone,
        'progress': t.quartersProgress(a.quartersRead, a.quarterCount),
        'endsAt': g.nextCycleAt?.millisecondsSinceEpoch ?? 0,
      };
    }
    _saveWards();
  }

  void removeWard(String groupId) {
    if (!_supported || _wards.remove(groupId) == null) return;
    _saveWards();
  }

  void _saveWards() {
    final t = _t;
    _save('widget_ward', {
      'empty': t.widgetNoWard,
      'doneText': t.widgetWardDone,
      'leftDays': t.widgetDaysLeft('{n}'),
      'leftHours': t.widgetHoursLeft('{n}'),
      'items': _wards.values.toList(),
    });
  }

  /// أذكار وأدعية قصيرة، والويدجت بيختار واحد لكل يوم.
  Future<void> _updateDhikr() async {
    try {
      final cats = await AdhkarRepository.instance.daily();
      final items = <String>[
        for (final c in cats)
          if (c.id == 'tasbeeh' || c.id == 'quranDuas' || c.id == 'prophetsDuas')
            for (final d in c.items)
              if (d.text != null && d.text!.length <= 140) d.text!,
      ];
      await _save('widget_dhikr', {'title': _t.widgetDhikrTitle, 'items': items});
    } catch (_) {}
  }
}
