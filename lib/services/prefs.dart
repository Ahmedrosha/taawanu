import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات محفوظة على الجهاز: اللغة، وحجم خط المصحف، وعدادات الأذكار.
class Prefs {
  Prefs._(this._p);

  static late Prefs instance;

  final SharedPreferences _p;

  static Future<void> init() async {
    instance = Prefs._(await SharedPreferences.getInstance());
  }

  Locale get locale => Locale(_p.getString('locale') ?? 'ar');

  /// system | light | dark
  ThemeMode get themeMode => ThemeMode.values.firstWhere((m) => m.name == _p.getString('themeMode'), orElse: () => ThemeMode.system);
  Future<void> setThemeMode(String v) => _p.setString('themeMode', v);
  Future<void> setLocale(Locale l) => _p.setString('locale', l.languageCode);

  double get readerFontSize => _p.getDouble('readerFontSize') ?? 26;
  Future<void> setReaderFontSize(double v) => _p.setDouble('readerFontSize', v);

  /// خط المصحف (اسم الخط في Google Fonts).
  /// 'KFGQPC Hafs' = خط مصحف المدينة (ملف جوه التطبيق)، والباقي من Google Fonts.
  static const readerFonts = ['KFGQPC Hafs', 'Amiri Quran', 'Scheherazade New', 'Amiri', 'Noto Naskh Arabic'];
  String get readerFont {
    final v = _p.getString('readerFont');
    return readerFonts.contains(v) ? v! : 'Amiri Quran';
  }

  Future<void> setReaderFont(String v) => _p.setString('readerFont', v);

  /// التجويد الملون في النص المتصل (بنص التنزيل).
  bool get textTajweed => _p.getBool('textTajweed') ?? false;
  Future<void> setTextTajweed(bool v) => _p.setBool('textTajweed', v);

  /// خط النص المتصل الفعلي: التجويد بنص التنزيل، فخط حفص بتاع المجمع بيتبدل بأميري قرآن.
  String get textFont => textTajweed && readerFont == 'KFGQPC Hafs' ? 'Amiri Quran' : readerFont;

  /// شكل القراءة: 'pages' = صفحات المصحف (الافتراضي)، 'text' = نص متصل بالحجم اللي يختاره.
  String get readerView => _p.getString('readerView') == 'text' ? 'text' : 'pages';
  Future<void> setReaderView(String v) => _p.setString('readerView', v);

  /// خط الصفحات: 'hafs' = خط حفص (جوه التطبيق)، 'qpc' = خطوط صفحات المجمع (بتتحمّل).
  /// شكل الصفحات: hafs (خط حفص) / qpc (خطوط المجمع) / tajweed (خطوط المجمع الملونة بالتجويد).
  String get pageStyle {
    final v = _p.getString('pageStyle');
    return v == 'qpc' || v == 'tajweed' ? v! : 'hafs';
  }
  Future<void> setPageStyle(String v) => _p.setString('pageStyle', v);

  /// عدادات الأذكار بتتصفر كل يوم.
  Map<String, int> adhkarCounts(String day) {
    if (_p.getString('adhkarDay') != day) return {};
    final raw = _p.getStringList('adhkarCounts') ?? const [];
    return {
      for (final e in raw)
        if (e.contains('=')) e.split('=').first: int.tryParse(e.split('=').last) ?? 0,
    };
  }

  Future<void> setAdhkarCounts(String day, Map<String, int> counts) async {
    await _p.setString('adhkarDay', day);
    await _p.setStringList('adhkarCounts', [for (final e in counts.entries) '${e.key}=${e.value}']);
  }

  // ---------- الورد الشخصي (على الموبايل بس) ----------

  String? get personalWardItems => _p.getString('personalWardItems');
  Future<void> setPersonalWardItems(String v) => _p.setString('personalWardItems', v);
  String? get personalWardDone => _p.getString('personalWardDone');
  Future<void> setPersonalWardDone(String v) => _p.setString('personalWardDone', v);
  String? get personalWardSeen => _p.getString('personalWardSeen');
  Future<void> setPersonalWardSeen(String v) => _p.setString('personalWardSeen', v);

  // ---------- الزكاة (على الموبايل بس) ----------

  String? get zakatData => _p.getString('zakatData');
  Future<void> setZakatData(String v) => _p.setString('zakatData', v);
  String? get metalPrices => _p.getString('metalPrices');
  Future<void> setMetalPrices(String v) => _p.setString('metalPrices', v);

  // ---------- وقت التلاوة ----------

  /// ثواني القراءة لكل يوم على الموبايل ده (آخر ٦٠ يوم).
  Map<String, int> get readingSeconds => {
        for (final e in _p.getStringList('readingSeconds') ?? const <String>[])
          if (e.contains('=')) e.split('=').first: int.tryParse(e.split('=').last) ?? 0,
      };

  Future<void> addReadingSeconds(String day, int seconds) async {
    final m = readingSeconds;
    m[day] = (m[day] ?? 0) + seconds;
    final keys = m.keys.toList()..sort();
    while (keys.length > 60) {
      m.remove(keys.removeAt(0));
    }
    await _p.setStringList('readingSeconds', [for (final e in m.entries) '${e.key}=${e.value}']);
  }

  // ---------- التسبيح ----------

  /// أذكار السبحة اللي المستخدم ضافها: نص|عدد.
  List<(String, int)> get tasbeehCustom => [
        for (final e in _p.getStringList('tasbeehCustom') ?? const <String>[])
          if (e.contains('|')) (e.substring(0, e.lastIndexOf('|')), int.tryParse(e.substring(e.lastIndexOf('|') + 1)) ?? 33),
      ];
  Future<void> setTasbeehCustom(List<(String, int)> v) =>
      _p.setStringList('tasbeehCustom', [for (final e in v) '${e.$1}|${e.$2}']);

  /// عدّادات السبحة النهارده: id=عدد (بتتصفّر مع يوم جديد).
  Map<String, int> tasbeehCounts(String day) {
    if (_p.getString('tasbeehDay') != day) return {};
    return {
      for (final e in _p.getStringList('tasbeehCounts') ?? const <String>[])
        if (e.contains('=')) e.substring(0, e.lastIndexOf('=')): int.tryParse(e.substring(e.lastIndexOf('=') + 1)) ?? 0,
    };
  }

  Future<void> setTasbeehCounts(String day, Map<String, int> counts) async {
    await _p.setString('tasbeehDay', day);
    await _p.setStringList('tasbeehCounts', [for (final e in counts.entries) '${e.key}=${e.value}']);
  }

  String? get tasbeehSelected => _p.getString('tasbeehSelected');
  Future<void> setTasbeehSelected(String id) => _p.setString('tasbeehSelected', id);

  // ---------- الصلاة ----------
  // الموقع بيتحفظ على الجهاز بس، ومبيتبعتش للسيرفر.

  double? get prayerLat => _p.getDouble('prayerLat');
  double? get prayerLng => _p.getDouble('prayerLng');

  /// اسم المكان (بالعربي والإنجليزي) لو اتحدد من القائمة أو لقينا مدينة قريبة.
  String? get prayerPlaceAr => _p.getString('prayerPlaceAr');
  String? get prayerPlaceEn => _p.getString('prayerPlaceEn');

  Future<void> setPrayerLocation(double lat, double lng, {String? placeAr, String? placeEn}) async {
    await _p.setDouble('prayerLat', lat);
    await _p.setDouble('prayerLng', lng);
    if (placeAr != null) {
      await _p.setString('prayerPlaceAr', placeAr);
    } else {
      await _p.remove('prayerPlaceAr');
    }
    if (placeEn != null) {
      await _p.setString('prayerPlaceEn', placeEn);
    } else {
      await _p.remove('prayerPlaceEn');
    }
  }

  /// طريقة الحساب (null = تلقائي حسب المكان).
  String? get prayerMethod => _p.getString('prayerMethod');
  Future<void> setPrayerMethod(String? v) => v == null ? _p.remove('prayerMethod') : _p.setString('prayerMethod', v);

  bool get asrHanafi => _p.getBool('asrHanafi') ?? false;
  Future<void> setAsrHanafi(bool v) => _p.setBool('asrHanafi', v);

  // ---------- تنبيهات الصلاة ----------

  bool get prayerAlerts => _p.getBool('prayerAlerts') ?? false;
  Future<void> setPrayerAlerts(bool v) => _p.setBool('prayerAlerts', v);

  /// الصلوات اللي عليها تنبيه (أسماء الـenum). الافتراضي: الخمسة.
  Set<String> get prayerAlertsFor =>
      (_p.getStringList('prayerAlertsFor') ?? const ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']).toSet();
  Future<void> setPrayerAlertsFor(Set<String> v) => _p.setStringList('prayerAlertsFor', v.toList());

  /// تذكير قبل الصلاة بالدقايق (٠ = من غير).
  int get prayerReminderMinutes => _p.getInt('prayerReminderMinutes') ?? 0;
  Future<void> setPrayerReminderMinutes(int v) => _p.setInt('prayerReminderMinutes', v);

  /// بيانات ويدجتس الشاشة الرئيسية (JSON)، بيقراها كود أندرويد من نفس الملف.
  Future<void> setWidgetData(String key, String json) => _p.setString(key, json);

  // ---------- التذكيرات (على الموبايل) ----------
  // المفاتيح: adhkarMorning / adhkarEvening / adhkarSleep / ward / kahf / salawat.

  static const reminderDefaults = {
    'adhkarMorning': 6 * 60 + 30,
    'adhkarEvening': 17 * 60,
    'adhkarSleep': 22 * 60 + 30,
    'ward': 21 * 60,
    'kahf': 9 * 60,
    'salawat': 14 * 60,
  };

  bool reminderOn(String key) => _p.getBool('rem_$key') ?? false;
  Future<void> setReminderOn(String key, bool v) => _p.setBool('rem_$key', v);

  /// وقت التذكير بالدقايق من نص الليل.
  int reminderMinutes(String key) => _p.getInt('remAt_$key') ?? reminderDefaults[key] ?? 9 * 60;
  Future<void> setReminderMinutes(String key, int v) => _p.setInt('remAt_$key', v);

  /// إشعارات المجموعات والرسائل (اللي بتيجي من السيرفر).
  bool get groupPush => _p.getBool('groupPush') ?? true;
  Future<void> setGroupPush(bool v) => _p.setBool('groupPush', v);

  // ---------- مكان القراءة ----------
  // آخر آية كانت أول الشاشة في كل ورد: "ربع:سورة:آية".

  String? readPosition(String key) => _p.getString('readPos:$key');
  Future<void> setReadPosition(String key, String v) => _p.setString('readPos:$key', v);
  Future<void> clearReadPosition(String key) async {
    await _p.remove('readPos:$key');
    await _p.remove('readPosAt:$key');
  }

  /// وقت آخر حفظ لمكان القراءة (عشان نقارنه باللي على السيرفر).
  int? readPositionAt(String key) => _p.getInt('readPosAt:$key');
  Future<void> setReadPositionAt(String key, int ms) => _p.setInt('readPosAt:$key', ms);

  // ---------- فلاتر وترتيب شاشة المجموعات ----------

  /// all | manage | member
  String get groupsRole => _p.getString('groupsRole') ?? 'all';
  Future<void> setGroupsRole(String v) => _p.setString('groupsRole', v);

  /// all | private | public
  String get groupsType => _p.getString('groupsType') ?? 'all';
  Future<void> setGroupsType(String v) => _p.setString('groupsType', v);

  /// حجم الورد بالأرباع (٠ = الكل).
  int get groupsWard => _p.getInt('groupsWard') ?? 0;
  Future<void> setGroupsWard(int v) => _p.setInt('groupsWard', v);

  /// recent | name | pending | size
  String get groupsSort => _p.getString('groupsSort') ?? 'recent';
  Future<void> setGroupsSort(String v) => _p.setString('groupsSort', v);

  /// المجموعات المثبّتة فوق.
  List<String> get pinnedGroups => _p.getStringList('pinnedGroups') ?? const [];
  Future<void> setPinnedGroups(List<String> v) => _p.setStringList('pinnedGroups', v);

  /// نصيحة "دوس على الآية للتفسير" بتظهر مرة واحدة.
  /// كارت "دليل الاستخدام" في الرئيسية اتقفل (أو الدليل اتفتح).
  bool get guideCardDone => _p.getBool('guideCardDone') ?? false;
  Future<void> setGuideCardDone() => _p.setBool('guideCardDone', true);

  /// الجولات التعريفية اللي اتشافت.
  bool tourDone(String id) => (_p.getStringList('toursDone') ?? const []).contains(id);
  Future<void> setTourDone(String id) async {
    final done = {...?_p.getStringList('toursDone'), id};
    await _p.setStringList('toursDone', done.toList());
  }

  Future<void> resetTours() => _p.remove('toursDone');

  bool get tafsirTipShown => _p.getBool('tafsirTipShown') ?? false;
  Future<void> setTafsirTipShown() => _p.setBool('tafsirTipShown', true);

  /// التفسير المختار في ورقة التفسير.
  String get tafsirId => _p.getString('tafsirId') ?? 'muyassar';
  Future<void> setTafsirId(String v) => _p.setString('tafsirId', v);

  /// القارئ المختار للتلاوة.
  String get reciterId => _p.getString('reciterId') ?? 'alafasy';
  Future<void> setReciterId(String v) => _p.setString('reciterId', v);

  /// تكرار كل آية في التلاوة: ١ أو ٣ أو ٥، و٠ = لحد ما يوقّف.
  /// لون تظليل الآية/الكلمة في القراءة.
  String get highlightColor => _p.getString('highlightColor') ?? 'gold';
  Future<void> setHighlightColor(String v) => _p.setString('highlightColor', v);

  /// القراءة التلقائية بتنوّر إيه: ayah / word / none.
  /// شريط "فيه تحديث" اتقفل لأنهي نسخة وإمتى.
  String? get updateDismissedFor => _p.getString('updateDismissedFor');
  DateTime? get updateDismissedAt {
    final v = _p.getInt('updateDismissedAt');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  Future<void> setUpdateDismissed(String version) async {
    await _p.setString('updateDismissedFor', version);
    await _p.setInt('updateDismissedAt', DateTime.now().millisecondsSinceEpoch);
  }

  /// آخر نسخة اتسجلت في حساب المستخدم (uid|version).
  String? get recordedVersion => _p.getString('recordedVersion');
  Future<void> setRecordedVersion(String v) => _p.setString('recordedVersion', v);

  /// ترتيب قايمة الأعضاء: points / name / oldest / newest / ward / status.
  String get memberSort => _p.getString('memberSort') ?? 'points';
  Future<void> setMemberSort(String v) => _p.setString('memberSort', v);

  String get autoReadMode => _p.getString('autoReadMode') ?? 'ayah';
  Future<void> setAutoReadMode(String v) => _p.setString('autoReadMode', v);

  /// سرعة القراءة التلقائية (×١ = ٦٠ كلمة في الدقيقة).
  double get autoReadSpeed => _p.getDouble('autoReadSpeed') ?? 1.0;
  Future<void> setAutoReadSpeed(double v) => _p.setDouble('autoReadSpeed', v);

  int get recitationRepeat => _p.getInt('recitationRepeat') ?? 1;
  Future<void> setRecitationRepeat(int v) => _p.setInt('recitationRepeat', v);
}
