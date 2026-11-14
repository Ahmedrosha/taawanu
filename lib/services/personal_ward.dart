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
  const PersonalItem({required this.id, required this.type, required this.ref, this.days = const [], this.since});

  /// 'adhkar' (ref = id القسم) | 'surah' (ref = رقم السورة).
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
  int get surah => int.tryParse(ref) ?? 1;

  bool dueOn(DateTime d) => days.isEmpty || days.contains(d.weekday);

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'ref': ref, 'days': days, if (since != null) 'since': since};

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

  void _itemsChanged() {
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
  bool isDone(PersonalItem i) => manuallyDone(i) || (!i.isSurah && _adhkarComplete(i.ref));

  /// ده اتعلّم تلقائي (الأذكار لما العدّاد يخلص)؟
  bool autoDone(PersonalItem i) => !i.isSurah && _adhkarComplete(i.ref);

  /// الأذكار اللي خلصت النهارده بتتسجّل في السجل (عشان تبان في التقرير).
  void _recordAuto() {
    if (_adhkar.isEmpty) return;
    final day = personalDayKey();
    var changed = false;
    for (final i in today()) {
      if (i.isSurah || !_adhkarComplete(i.ref)) continue;
      final list = _doneMap.putIfAbsent(day, () => []);
      if (!list.contains(i.id)) {
        list.add(i.id);
        changed = true;
      }
    }
    final before = _dirtyDays.length;
    _noteDue();
    if (changed || _dirtyDays.length != before) {
      _dirtyDays.add(day);
      _saveDone();
      _schedulePush();
    }
  }

  int get doneCount => today().where(isDone).length;

  Future<void> setDone(PersonalItem i, bool done) async {
    final day = personalDayKey();
    final list = _doneMap.putIfAbsent(day, () => []);
    if (done) {
      if (!list.contains(i.id)) list.add(i.id);
    } else {
      list.remove(i.id);
    }
    _dirtyDays.add(day);
    _noteDue();
    notifyListeners();
    await _saveDone();
    _schedulePush();
  }

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
