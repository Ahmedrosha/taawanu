import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/adhkar/adhkar_data.dart';
import 'mushaf_layout.dart';
import 'prefs.dart';
import 'quran_repository.dart';

/// بند في الورد الشخصي: أذكار (قسم كامل) أو سورة كاملة.
class PersonalItem {
  const PersonalItem({required this.id, required this.type, required this.ref, this.days = const [], this.since, this.remindAt, this.khatma});

  /// ميعاد تذكير خاص بالبند (دقايق من نص الليل)، أو null.
  final int? remindAt;

  /// حالة الختمة الشخصية (للنوع 'khatma' بس).
  final KhatmaPlan? khatma;

  PersonalItem withRemind(int? minutes) =>
      PersonalItem(id: id, type: type, ref: ref, days: days, since: since, remindAt: minutes, khatma: khatma);

  PersonalItem withKhatma(KhatmaPlan k) =>
      PersonalItem(id: id, type: type, ref: ref, days: days, since: since, remindAt: remindAt, khatma: k);

  /// 'adhkar' (ref = id القسم) | 'surah' (ref = رقم السورة) | 'khatma' (ختمة شخصية، ref = 'k').
  final String id;
  final String type;
  final String ref;

  /// أيام الأسبوع (١ = الاثنين … ٧ = الأحد). فاضية = كل يوم.
  final List<int> days;

  /// يوم الإضافة (للتقرير). القديم من غيره: من الـ id (وقت الإضافة بالميكروثانية).
  final String? since;

  DateTime get sinceDate {
    final d = since == null ? null : parseDayKey(since!);
    if (d != null) return d;
    final us = int.tryParse(id);
    if (us == null) return DateTime(2026);
    final t = DateTime.fromMicrosecondsSinceEpoch(us);
    return DateTime(t.year, t.month, t.day);
  }

  bool get isSurah => type == 'surah';
  bool get isAdhkar => type == 'adhkar';
  bool get isKhatma => type == 'khatma';
  int get surah => int.tryParse(ref) ?? 1;

  /// مطلوب في اليوم ده؟ (الختمة اللي خلصت مبتبقاش مطلوبة غير يوم ما ختمت).
  bool dueOn(DateTime d) {
    if (!(days.isEmpty || days.contains(d.weekday))) return false;
    final k = khatma;
    if (k != null && k.finished && k.curDay != personalDayKey(d)) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'ref': ref,
        'days': days,
        if (since != null) 'since': since,
        if (remindAt != null) 'remindAt': remindAt,
        if (khatma != null) 'k': khatma!.toJson(),
      };

  static PersonalItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], type = j['type'], ref = j['ref'];
    if (id is! String || type is! String || ref is! String) return null;
    return PersonalItem(
      id: id,
      type: type,
      ref: ref,
      days: [for (final d in (j['days'] as List? ?? const [])) if (d is int && d >= 1 && d <= 7) d],
      since: j['since'] is String ? j['since'] as String : null,
      remindAt: j['remindAt'] is int && (j['remindAt'] as int) >= 0 && (j['remindAt'] as int) < 1440 ? j['remindAt'] as int : null,
      khatma: KhatmaPlan.fromJson(j['k']),
    );
  }
}

/// الختمة الشخصية: كل يوم ورد بالأرباع (١..٢٤٠)، ولما يخلص بكره يجي اللي بعده.
class KhatmaPlan {
  const KhatmaPlan({
    required this.perDay,
    required this.start,
    required this.pos,
    required this.startedAt,
    this.strict = false,
    this.count = 0,
    this.curDay,
    this.curFrom,
    this.curTo,
    this.finished = false,
  });

  /// أرباع كل يوم.
  final int perDay;

  /// أول ربع في الختمة دي (للنسبة)، واللي جاي يتقري.
  final int start;
  final int pos;

  /// يوم بداية الختمة دي.
  final String startedAt;

  /// "ألتزم بالميعاد": اللي فات بيتضاف. غيره: الورد يستناك.
  final bool strict;

  /// الختمات اللي خلصت قبل كده.
  final int count;

  /// ورد اليوم اللي اتعلّم "تمت" (عشان يفضل باين بعد ما يخلص).
  final String? curDay;
  final int? curFrom;
  final int? curTo;

  /// ختم (لحد ما يبدأ ختمة جديدة).
  final bool finished;

  KhatmaPlan copy({int? pos, int? start, String? startedAt, int? count, String? curDay, int? curFrom, int? curTo, bool? finished, bool clearCur = false}) =>
      KhatmaPlan(
        perDay: perDay,
        start: start ?? this.start,
        pos: pos ?? this.pos,
        startedAt: startedAt ?? this.startedAt,
        strict: strict,
        count: count ?? this.count,
        curDay: clearCur ? null : (curDay ?? this.curDay),
        curFrom: clearCur ? null : (curFrom ?? this.curFrom),
        curTo: clearCur ? null : (curTo ?? this.curTo),
        finished: finished ?? this.finished,
      );

  Map<String, dynamic> toJson() => {
        'perDay': perDay,
        'start': start,
        'pos': pos,
        'startedAt': startedAt,
        'strict': strict,
        'count': count,
        if (curDay != null) 'curDay': curDay,
        if (curFrom != null) 'curFrom': curFrom,
        if (curTo != null) 'curTo': curTo,
        'finished': finished,
      };

  static KhatmaPlan? fromJson(Object? j) {
    if (j is! Map) return null;
    int? n(Object? v) => v is num ? v.toInt() : null;
    final perDay = n(j['perDay']), start = n(j['start']), pos = n(j['pos']);
    final startedAt = j['startedAt'];
    if (perDay == null || start == null || pos == null || startedAt is! String) return null;
    return KhatmaPlan(
      perDay: perDay.clamp(1, 240),
      start: start.clamp(1, 240),
      pos: pos.clamp(1, 241),
      startedAt: startedAt,
      strict: j['strict'] == true,
      count: n(j['count']) ?? 0,
      curDay: j['curDay'] is String ? j['curDay'] as String : null,
      curFrom: n(j['curFrom']),
      curTo: n(j['curTo']),
      finished: j['finished'] == true,
    );
  }
}

String personalDayKey([DateTime? d]) {
  final n = d ?? DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}

DateTime? parseDayKey(String k) {
  final p = k.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  return y == null || m == null || d == null ? null : DateTime(y, m, d);
}

/// الورد الشخصي: قايمة أهداف يومية (أذكار وسور) محفوظة على الموبايل بس، ومعاها اللي اتعلّم "تم".
/// الأذكار بتتعلّم لما عدّاد القسم يخلص، والسورة لما صفحاتها كلها تتفتح في المصحف الحر، أو بإيدك.
class PersonalWard extends ChangeNotifier {
  PersonalWard._();
  static final instance = PersonalWard._();

  List<PersonalItem>? _items;
  Map<String, List<String>>? _done;
  Map<String, int>? _due;
  List<AdhkarCategory> _adhkar = const [];
  String? _seenDay;
  final Set<int> _seen = {};
  int? _lastPage;

  List<PersonalItem> get items => _items ??= _loadItems();

  List<PersonalItem> _loadItems() {
    try {
      final raw = Prefs.instance.personalWardItems;
      if (raw == null) return [];
      return [for (final j in jsonDecode(raw) as List) if (PersonalItem.fromJson(j) case final i?) i];
    } catch (_) {
      return [];
    }
  }

  Map<String, List<String>> get _doneMap => _done ??= () {
        try {
          final raw = Prefs.instance.personalWardDone;
          if (raw == null) return <String, List<String>>{};
          return {
            for (final e in (jsonDecode(raw) as Map).entries) e.key as String: List<String>.from(e.value as List),
          };
        } catch (_) {
          return <String, List<String>>{};
        }
      }();

  /// عدد البنود المطلوبة في كل يوم (للتقرير).
  Map<String, int> get _dueMap => _due ??= () {
        try {
          final raw = Prefs.instance.personalWardDue;
          if (raw == null) return <String, int>{};
          return {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: (e.value as num).toInt()};
        } catch (_) {
          return <String, int>{};
        }
      }();

  /// اللي اتعمل في يوم (للتقرير).
  List<String> doneOn(String day) => _doneMap[day] ?? const [];

  /// عدد المطلوب في يوم اتسجّل (أو null لو اليوم مالوش سجل).
  int? dueOn(String day) => _dueMap[day];

  /// أقسام الأذكار (للحكم على الأذكار الخلصت).
  Future<void> loadAdhkar() async {
    _adhkar = await AdhkarRepository.instance.daily();
    _recordAuto();
    notifyListeners();
  }

  List<AdhkarCategory> get adhkarCategories => _adhkar;

  Future<void> _saveItems() => Prefs.instance.setPersonalWardItems(jsonEncode([for (final i in items) i.toJson()]));

  Future<void> _saveDone() async {
    // السجل: آخر ٤٠٠ يوم (للتقرير).
    final cut = DateTime.now().subtract(const Duration(days: 400));
    _doneMap.removeWhere((k, _) => parseDayKey(k)?.isBefore(cut) ?? true);
    _dueMap.removeWhere((k, _) => parseDayKey(k)?.isBefore(cut) ?? true);
    await Prefs.instance.setPersonalWardDone(jsonEncode(_doneMap));
    await Prefs.instance.setPersonalWardDue(jsonEncode(_dueMap));
  }

  /// عدد المطلوب النهارده بيتسجّل مع السجل.
  void _noteDue() {
    final day = personalDayKey();
    final n = today().length;
    if (_dueMap[day] == n) return;
    _dueMap[day] = n;
    _dirtyDays.add(day);
  }

  Future<void> add(PersonalItem item) async {
    items.add(item);
    _itemsChanged();
    notifyListeners();
    await _saveItems();
    await _saveDone();
    _schedulePush();
  }

  Future<void> remove(String id) async {
    items.removeWhere((i) => i.id == id);
    _itemsChanged();
    notifyListeners();
    await _saveItems();
    await _saveDone();
    _schedulePush();
  }

  /// ميعاد تذكير البند اتغير.
  Future<void> setRemind(String id, int? minutes) async {
    final k = items.indexWhere((i) => i.id == id);
    if (k < 0) return;
    items[k] = items[k].withRemind(minutes);
    _itemsChanged();
    notifyListeners();
    await _saveItems();
    _schedulePush();
  }

  /// بيتنده لما حاجة تأثر على التذكيرات تتغير (بند اتضاف/اتشال/اتعمل).
  void Function()? onScheduleChanged;

  void _itemsChanged() {
    onScheduleChanged?.call();
    _itemsDirty = true;
    Prefs.instance.setPersonalWardItemsAt(DateTime.now().millisecondsSinceEpoch);
    _noteDue();
  }

  bool has(String type, String ref) => items.any((i) => i.type == type && i.ref == ref);

  List<PersonalItem> today([DateTime? d]) {
    final day = d ?? DateTime.now();
    return [for (final i in items) if (i.dueOn(day)) i];
  }

  bool _adhkarComplete(String categoryId) {
    final cat = _adhkar.where((c) => c.id == categoryId).firstOrNull;
    if (cat == null || cat.items.isEmpty) return false;
    final counts = Prefs.instance.adhkarCounts(personalDayKey());
    return cat.items.every((d) => (counts[d.id] ?? 0) >= d.count);
  }

  bool manuallyDone(PersonalItem i, [String? day]) => _doneMap[day ?? personalDayKey()]?.contains(i.id) ?? false;

  /// خلص النهارده: تلقائي (أذكار أو سورة اتقرت) أو بإيدك.
  bool isDone(PersonalItem i) => manuallyDone(i) || (i.isAdhkar && _adhkarComplete(i.ref));

  /// ده اتعلّم تلقائي (الأذكار لما العدّاد يخلص)؟
  bool autoDone(PersonalItem i) => i.isAdhkar && _adhkarComplete(i.ref);

  /// الأذكار اللي خلصت النهارده بتتسجّل في السجل (عشان تبان في التقرير).
  void _recordAuto() {
    if (_adhkar.isEmpty) return;
    final day = personalDayKey();
    var changed = false;
    for (final i in today()) {
      if (!i.isAdhkar || !_adhkarComplete(i.ref)) continue;
      final list = _doneMap.putIfAbsent(day, () => []);
      if (!list.contains(i.id)) {
        list.add(i.id);
        changed = true;
      }
    }
    final before = _dirtyDays.length;
    _noteDue();
    if (changed) onScheduleChanged?.call();
    if (changed || _dirtyDays.length != before) {
      _dirtyDays.add(day);
      _saveDone();
      _schedulePush();
    }
  }

  int get doneCount => today().where(isDone).length;

  Future<void> setDone(PersonalItem i, bool done) async {
    final day = personalDayKey();
    if (i.isKhatma) _khatmaDone(i, done, day);
    final list = _doneMap.putIfAbsent(day, () => []);
    if (done) {
      if (!list.contains(i.id)) list.add(i.id);
    } else {
      list.remove(i.id);
    }
    _dirtyDays.add(day);
    _noteDue();
    onScheduleChanged?.call();
    notifyListeners();
    await _saveDone();
    _schedulePush();
  }

  /// أقسام الأذكار من غير إشعار (للتذكيرات).
  Future<void> ensureAdhkar() async {
    if (_adhkar.isEmpty) _adhkar = await AdhkarRepository.instance.daily();
  }

  // ---------- الختمة الشخصية ----------

  PersonalItem? get khatmaItem => items.where((i) => i.isKhatma && i.khatma != null).firstOrNull;

  /// عدد الأيام المطلوبة من يوم البداية لحد [d] (بما فيهم).
  int _dueDaysBetween(PersonalItem i, DateTime from, DateTime to) {
    var n = 0;
    for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      if (i.days.isEmpty || i.days.contains(d.weekday)) n++;
      if (n > 4000) break;
    }
    return n;
  }

  /// ورد النهارده في الختمة (من ربع لربع)، أو null لو ختم.
  (int, int)? khatmaToday(PersonalItem i) {
    final k = i.khatma;
    if (k == null) return null;
    final day = personalDayKey();
    if (k.curDay == day && k.curFrom != null && k.curTo != null) return (k.curFrom!, k.curTo!);
    if (k.pos > 240) return null;
    var to = k.pos + k.perDay - 1;
    if (k.strict) {
      // ألتزم بالميعاد: لحد المفروض أكون وصلته النهارده.
      final start = parseDayKey(k.startedAt) ?? DateTime.now();
      final expected = k.start - 1 + k.perDay * _dueDaysBetween(i, start, DateTime.now());
      if (expected > to) to = expected;
    }
    return (k.pos, to > 240 ? 240 : to);
  }

  /// الورد اللي بعده (لـ"اقرأ ورد بكره") بعد ما ورد النهارده يخلص.
  (int, int)? khatmaNext(PersonalItem i) {
    final k = i.khatma;
    if (k == null || k.pos > 240 || !isDone(i)) return null;
    final to = k.pos + k.perDay - 1;
    return (k.pos, to > 240 ? 240 : to);
  }

  /// نسبة الختمة (من أول الختمة دي).
  double khatmaProgress(PersonalItem i) {
    final k = i.khatma;
    if (k == null) return 0;
    final total = 241 - k.start;
    return total <= 0 ? 1 : ((k.pos - k.start) / total).clamp(0.0, 1.0);
  }

  /// التاريخ المتوقع للختم (على الأيام المطلوبة).
  DateTime? khatmaEta(PersonalItem i) {
    final k = i.khatma;
    if (k == null || k.pos > 240) return null;
    var left = ((241 - k.pos) / k.perDay).ceil();
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    if (isDone(i)) d = DateTime(d.year, d.month, d.day + 1);
    for (var guard = 0; guard < 4000; guard++) {
      if (i.days.isEmpty || i.days.contains(d.weekday)) {
        left--;
        if (left <= 0) return d;
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return null;
  }

  void _replace(PersonalItem i, KhatmaPlan k) {
    final idx = items.indexWhere((x) => x.id == i.id);
    if (idx < 0) return;
    items[idx] = i.withKhatma(k);
    _itemsChanged();
    _saveItems();
  }

  /// تعليم ورد النهارده: المكان بيتقدّم (أو يرجع لو اتشال التعليم).
  void _khatmaDone(PersonalItem i, bool done, String day) {
    final cur = items.where((x) => x.id == i.id).firstOrNull ?? i;
    final k = cur.khatma;
    if (k == null) return;
    if (done) {
      if (k.curDay == day) return; // متعلّم قبل كده
      final r = khatmaToday(cur);
      if (r == null) return;
      final next = r.$2 + 1;
      final fin = next > 240;
      _replace(cur, k.copy(curDay: day, curFrom: r.$1, curTo: r.$2, pos: next, finished: fin, count: fin ? k.count + 1 : k.count));
    } else if (k.curDay == day && k.curFrom != null) {
      _replace(cur, k.copy(pos: k.curFrom, finished: false, count: k.finished ? k.count - 1 : k.count, clearCur: true));
    }
  }

  /// ورد زيادة ("اقرأ ورد بكره") اتقرا: المكان يتقدّم من غير ما يعلّم بكره.
  Future<void> khatmaAdvance(PersonalItem i, int from, int to) async {
    final cur = items.where((x) => x.id == i.id).firstOrNull;
    final k = cur?.khatma;
    if (cur == null || k == null || k.pos != from) return;
    final next = to + 1;
    final fin = next > 240;
    _replace(cur, k.copy(pos: next, finished: fin, count: fin ? k.count + 1 : k.count));
    notifyListeners();
    _schedulePush();
  }

  /// ختمة جديدة بنفس النظام (من الفاتحة).
  Future<void> khatmaRestart(PersonalItem i) async {
    final cur = items.where((x) => x.id == i.id).firstOrNull;
    final k = cur?.khatma;
    if (cur == null || k == null) return;
    _replace(cur, k.copy(start: 1, pos: 1, startedAt: personalDayKey(), finished: false, clearCur: true));
    notifyListeners();
    _schedulePush();
  }

  /// عدد التذكيرات اللي الورد الشخصي محتاجها (عشان حد الآيفون: ٦٤ إشعار مجدول).
  int get reminderSlots {
    if (items.isEmpty) return 0;
    final general = Prefs.instance.reminderOn('personal') ? 2 : 0;
    final own = items.where((i) => i.remindAt != null).length;
    return general + (own > maxItemReminders ? maxItemReminders : own);
  }

  static const maxItemReminders = 12;

  // ---------- الحفظ في الحساب (users/{uid}/private/personalWard) ----------
  // البنود بتتبعت كاملة مع وقت آخر تعديل، والسجل يوم بيوم (دمج)، عشان جهازين مايمسحوش بعض.

  final Set<String> _dirtyDays = {};
  bool _itemsDirty = false;
  Timer? _pushTimer;
  String? _syncedUid;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('private').doc('personalWard');
  }

  /// الخروج من الحساب: نبعت آخر تعديلات، ونمسح الورد من الموبايل (عشان الحساب الجاي ميشوفهوش).
  Future<void> signOut() async {
    _pushTimer?.cancel();
    try {
      await _push().timeout(const Duration(seconds: 5));
    } catch (_) {}
    _items = null;
    _done = null;
    _due = null;
    _dirtyDays.clear();
    _itemsDirty = false;
    _syncedUid = null;
    _seenDay = null;
    _seen.clear();
    await Prefs.instance.clearPersonalWard();
    notifyListeners();
  }

  /// أول مرة بعد الدخول: ندمج اللي في الحساب مع اللي على الموبايل، ونبعت الناقص.
  Future<void> sync() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final doc = _doc;
    if (uid == null || doc == null || uid == _syncedUid) return;
    _syncedUid = uid;
    try {
      final data = (await doc.get()).data();
      if (data != null) _merge(data);
      // كل اللي على الموبايل يتبعت (الدمج في السيرفر يوم بيوم).
      _dirtyDays.addAll({..._doneMap.keys, ..._dueMap.keys});
      _itemsDirty = true;
      await _push();
    } catch (e) {
      _syncedUid = null;
      debugPrint('personal ward sync failed: $e');
    }
  }

  void _merge(Map<String, dynamic> data) {
    final remoteAt = (data['itemsAt'] as num?)?.toInt() ?? 0;
    final localAt = Prefs.instance.personalWardItemsAt ?? 0;
    final remoteItems = data['items'];
    if (remoteAt > localAt && remoteItems is List) {
      _items = [for (final j in remoteItems) if (PersonalItem.fromJson(j) case final i?) i];
      Prefs.instance.setPersonalWardItemsAt(remoteAt);
      _saveItems();
      onScheduleChanged?.call();
    }
    final done = data['done'];
    if (done is Map) {
      done.forEach((k, v) {
        if (k is! String || v is! List) return;
        final list = _doneMap.putIfAbsent(k, () => []);
        for (final id in v) {
          if (id is String && !list.contains(id)) list.add(id);
        }
      });
    }
    final due = data['due'];
    if (due is Map) {
      due.forEach((k, v) {
        if (k is! String || v is! num) return;
        final n = v.toInt();
        if ((_dueMap[k] ?? -1) < n) _dueMap[k] = n;
      });
    }
    _saveDone();
    notifyListeners();
  }

  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), _push);
  }

  Future<void> _push() async {
    final doc = _doc;
    if (doc == null || _syncedUid == null) return;
    if (!_itemsDirty && _dirtyDays.isEmpty) return;
    final days = Set<String>.from(_dirtyDays);
    final withItems = _itemsDirty;
    _dirtyDays.clear();
    _itemsDirty = false;
    try {
      await doc.set({
        if (withItems) 'items': [for (final i in items) i.toJson()],
        if (withItems) 'itemsAt': Prefs.instance.personalWardItemsAt ?? DateTime.now().millisecondsSinceEpoch,
        if (days.isNotEmpty) 'done': {for (final d in days) d: _doneMap[d] ?? const <String>[]},
        if (days.isNotEmpty) 'due': {for (final d in days) if (_dueMap[d] != null) d: _dueMap[d]},
        'at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // من غير نت أو مرفوض: نرجّعها وتتبعت المرة الجاية.
      _dirtyDays.addAll(days);
      _itemsDirty = _itemsDirty || withItems;
      debugPrint('personal ward push failed: $e');
    }
  }

  // ---------- المصحف الحر: الصفحات اللي اتفتحت النهارده ----------

  void _loadSeen() {
    final day = personalDayKey();
    if (_seenDay == day) return;
    _seenDay = day;
    _seen.clear();
    _lastPage = null;
    try {
      final raw = Prefs.instance.personalWardSeen;
      if (raw != null) {
        final d = jsonDecode(raw) as Map;
        if (d['day'] == day) _seen.addAll([for (final p in d['pages'] as List) p as int]);
      }
    } catch (_) {}
  }

  /// المصحف اتفتح من جديد: آخر صفحة من الجلسة اللي فاتت مبتتحسبش "اللي قبلها".
  void resetCursor() => _lastPage = null;

  /// عدّادات الأذكار اتغيّرت: نسجّل اللي خلص، واللي بيعرض الورد يتحدّث.
  void touch() {
    _recordAuto();
    notifyListeners();
  }

  /// صفحة اتفتحت في المصحف الحر. بترجّع السور اللي خلصت بسببها (عشان الإشعار).
  List<int> notePage(int page, MushafLayout layout, QuranData quran) {
    _loadSeen();
    final last = _lastPage;
    _lastPage = page;
    final added = <int>[];
    if (_seen.add(page)) added.add(page);
    // تقليب لقدام بخطوة صغيرة: الصفحات اللي بينهم اتشافت كمان (النص المتصل مبيبعتش كل صفحة).
    if (last != null && page > last && page - last <= 3) {
      for (var p = last + 1; p < page; p++) {
        if (_seen.add(p)) added.add(p);
      }
    }
    if (added.isEmpty) return const [];
    Prefs.instance.setPersonalWardSeen(jsonEncode({'day': _seenDay, 'pages': _seen.toList()}));
    final finished = <int>[];
    for (final i in today()) {
      if (i.isKhatma && !isDone(i)) {
        // ورد الختمة النهارده: لو صفحاته كلها اتفتحت.
        final r = khatmaToday(i);
        if (r == null) continue;
        final (s1, a1) = quran.quarterStart(r.$1);
        final (s2, a2) = quran.quarterEnd(r.$2);
        var all = true;
        for (var p = layout.pageOf(s1, a1); p <= layout.endPageOf(s2, a2); p++) {
          if (!_seen.contains(p)) {
            all = false;
            break;
          }
        }
        if (all) {
          finished.add(0); // ٠ = ورد الختمة
          setDone(i, true);
        }
        continue;
      }
      if (!i.isSurah || isDone(i)) continue;
      final s = i.surah;
      final from = layout.pageOf(s, 1), to = layout.endPageOf(s, quran.ayahCount(s));
      var all = true;
      for (var p = from; p <= to; p++) {
        if (!_seen.contains(p)) {
          all = false;
          break;
        }
      }
      if (all) {
        finished.add(s);
        setDone(i, true);
      }
    }
    return finished;
  }
}
