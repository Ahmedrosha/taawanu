import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../features/adhkar/adhkar_data.dart';
import 'mushaf_layout.dart';
import 'prefs.dart';
import 'quran_repository.dart';

/// بند في الورد الشخصي: أذكار (قسم كامل) أو سورة كاملة.
class PersonalItem {
  const PersonalItem({required this.id, required this.type, required this.ref, this.days = const []});

  /// 'adhkar' (ref = id القسم) | 'surah' (ref = رقم السورة).
  final String id;
  final String type;
  final String ref;

  /// أيام الأسبوع (١ = الاثنين … ٧ = الأحد). فاضية = كل يوم.
  final List<int> days;

  bool get isSurah => type == 'surah';
  int get surah => int.tryParse(ref) ?? 1;

  bool dueOn(DateTime d) => days.isEmpty || days.contains(d.weekday);

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'ref': ref, 'days': days};

  static PersonalItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], type = j['type'], ref = j['ref'];
    if (id is! String || type is! String || ref is! String) return null;
    return PersonalItem(
      id: id,
      type: type,
      ref: ref,
      days: [for (final d in (j['days'] as List? ?? const [])) if (d is int && d >= 1 && d <= 7) d],
    );
  }
}

String personalDayKey([DateTime? d]) {
  final n = d ?? DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}

/// الورد الشخصي: قايمة أهداف يومية (أذكار وسور) محفوظة على الموبايل بس، ومعاها اللي اتعلّم "تم".
/// الأذكار بتتعلّم لما عدّاد القسم يخلص، والسورة لما صفحاتها كلها تتفتح في المصحف الحر، أو بإيدك.
class PersonalWard extends ChangeNotifier {
  PersonalWard._();
  static final instance = PersonalWard._();

  List<PersonalItem>? _items;
  Map<String, List<String>>? _done;
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

  /// أقسام الأذكار (للحكم على الأذكار الخلصت).
  Future<void> loadAdhkar() async {
    _adhkar = await AdhkarRepository.instance.daily();
    notifyListeners();
  }

  List<AdhkarCategory> get adhkarCategories => _adhkar;

  Future<void> _saveItems() => Prefs.instance.setPersonalWardItems(jsonEncode([for (final i in items) i.toJson()]));

  Future<void> _saveDone() async {
    // آخر ١٤ يوم بس.
    final keys = _doneMap.keys.toList();
    if (keys.length > 14) {
      for (final k in keys.take(keys.length - 14)) {
        _doneMap.remove(k);
      }
    }
    await Prefs.instance.setPersonalWardDone(jsonEncode(_doneMap));
  }

  Future<void> add(PersonalItem item) async {
    items.add(item);
    notifyListeners();
    await _saveItems();
  }

  Future<void> remove(String id) async {
    items.removeWhere((i) => i.id == id);
    notifyListeners();
    await _saveItems();
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

  /// ده اتعلّم تلقائي (من غير ما تدوس عليه)؟
  bool autoDone(PersonalItem i) => !i.isSurah && !manuallyDone(i) && _adhkarComplete(i.ref);

  int get doneCount => today().where(isDone).length;

  Future<void> setDone(PersonalItem i, bool done) async {
    final day = personalDayKey();
    final list = _doneMap.putIfAbsent(day, () => []);
    if (done) {
      if (!list.contains(i.id)) list.add(i.id);
    } else {
      list.remove(i.id);
    }
    notifyListeners();
    await _saveDone();
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
