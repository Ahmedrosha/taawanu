import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/personal_ward.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../adhkar/adhkar_data.dart';
import '../adhkar/adhkar_screen.dart' show DhikrListScreen;
import '../groups/group_board_screen.dart' show ReadRequest;
import '../prayer/prayer_alerts.dart';
import 'personal_report_screen.dart';

/// كمية ورد الختمة بالكلام: ربع، حزب، جزء، جزئين، أو عدد أرباع.
String khatmaAmount(AppLocalizations t, int quarters) => switch (quarters) {
      1 => t.khatmaQuarter,
      4 => t.khatmaHizb,
      8 => t.khatmaJuz,
      16 => t.khatmaTwoJuz,
      _ => t.khatmaQuarters(quarters),
    };

/// اسم البند: القسم بالعربي أو الإنجليزي، أو اسم السورة، أو ورد الختمة النهارده.
String personalItemTitle(AppLocalizations t, PersonalItem i, QuranData? q, List<AdhkarCategory> adhkar, bool en) {
  if (i.isKhatma) {
    final r = PersonalWard.instance.khatmaToday(i);
    return r == null ? t.khatmaDoneTile : t.personalKhatmaTitle(rangeLabel(t, r.$1, r.$2));
  }
  if (i.isSurah) {
    final names = q == null ? null : (en ? q.surahNamesEn : q.surahNamesAr);
    final name = names == null ? '${i.surah}' : names[i.surah - 1];
    // الأسماء العربي فيها كلمة "سورة" أصلًا.
    return en ? t.personalSurahTitle(name) : name;
  }
  final c = adhkar.where((c) => c.id == i.ref).firstOrNull;
  if (c == null) return i.ref;
  // اسم القسم لوحده ("الصباح") مش واضح في الورد، فبنقول "أذكار الصباح".
  if (en) return c.en.toLowerCase().contains('adhkar') ? c.en : '${c.en} adhkar';
  return c.ar.contains('أذكار') ? c.ar : 'أذكار ${c.ar}';
}

String _daysLabel(AppLocalizations t, PersonalItem i, String locale) {
  if (i.days.isEmpty) return t.personalEveryDay;
  if (i.days.length == 1 && i.days.first == DateTime.friday) return t.personalFridayOnly;
  // ١ = الاثنين: 2 يناير 2023 كان اثنين.
  return [for (final d in i.days) DateFormat.E(locale).format(DateTime(2023, 1, 1 + d))].join(' · ');
}

String _timeLabel(BuildContext context, int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

/// ميعاد تذكير لبند (وبنطلب إذن الإشعارات لو لسه).
Future<int?> _pickRemindTime(BuildContext context, int? current) async {
  final m = current ?? 20 * 60;
  final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
  if (picked == null) return null;
  await PrayerAlerts.instance.requestPermission();
  return picked.hour * 60 + picked.minute;
}

/// الورد الشخصي: مصحف حر + قايمة أهداف يومية (أذكار وسور).
class PersonalWardScreen extends StatefulWidget {
  const PersonalWardScreen({super.key});

  @override
  State<PersonalWardScreen> createState() => _PersonalWardScreenState();
}

class _PersonalWardScreenState extends State<PersonalWardScreen> {
  final _ward = PersonalWard.instance;
  late final Future<QuranData> _quran = QuranRepository.instance.load();

  @override
  void initState() {
    super.initState();
    _ward.addListener(_changed);
    _ward.loadAdhkar();
  }

  @override
  void dispose() {
    _ward.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _openRead({int? surah, int? ayah, bool goal = false}) async {
    final t = AppLocalizations.of(context);
    await context.push('/read', extra: ReadRequest.personal(label: t.personalFreeMushaf, surah: surah, ayah: ayah, goal: goal));
    if (mounted) setState(() {});
  }

  Future<void> _openItem(PersonalItem i) async {
    final en = Localizations.localeOf(context).languageCode == 'en';
    final t = AppLocalizations.of(context);
    if (i.isSurah) return _openRead(surah: i.surah, goal: true);
    if (i.isKhatma) {
      final r = _ward.khatmaToday(i);
      if (r == null) return;
      return _openKhatma(r.$1, r.$2);
    }
    final cat = _ward.adhkarCategories.where((c) => c.id == i.ref).firstOrNull;
    if (cat == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DhikrListScreen(title: personalItemTitle(t, i, null, _ward.adhkarCategories, en), sections: [cat]),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _openKhatma(int from, int to) async {
    final t = AppLocalizations.of(context);
    await context.push('/read', extra: ReadRequest.khatma(label: t.personalKhatmaTitle(rangeLabel(t, from, to)), from: from, to: to));
    if (mounted) setState(() {});
  }


  /// ختم: تهنئة، وبعدها يختار يبدأ ختمة جديدة بنفس النظام، أو يغيّر، أو بعدين.
  void _maybeCelebrate(QuranData? q) {
    final item = _ward.khatmaItem;
    final k = item?.khatma;
    if (item == null || k == null || !k.finished || Prefs.instance.khatmaCelebrated == k.count) return;
    Prefs.instance.setKhatmaCelebrated(k.count);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('🎉  ${t.khatmaFinishedTitle}', textAlign: TextAlign.center),
          content: Text(t.khatmaFinishedBody(k.count), textAlign: TextAlign.center, style: const TextStyle(height: 1.8)),
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context, 'restart'), child: Text(t.khatmaRestart)),
            TextButton(onPressed: () => Navigator.pop(context, 'change'), child: Text(t.khatmaChange)),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t.khatmaLater)),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'restart') await _ward.khatmaRestart(item);
      if (choice == 'change' && q != null) {
        await _ward.remove(item.id);
        if (mounted) await _add(q, khatma: true);
      }
    });
  }

  Future<void> _goTo(QuranData q) async {
    final pos = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GoToSheet(quran: q),
    );
    if (pos != null) _openRead(surah: pos.$1, ayah: pos.$2);
  }

  Future<void> _add(QuranData q, {bool khatma = false}) async {
    final items = await showModalBottomSheet<List<PersonalItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddSheet(quran: q, adhkar: _ward.adhkarCategories, khatma: khatma),
    );
    if (items == null) return;
    for (final item in items) {
      if (!_ward.has(item.type, item.ref)) await _ward.add(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final en = locale == 'en';
    return Scaffold(
      appBar: AppBar(title: Text(t.personalWard, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: FutureBuilder<QuranData>(
        future: _quran,
        builder: (context, snap) {
          final q = snap.data;
          _maybeCelebrate(q);
          final today = _ward.today();
          final later = [for (final i in _ward.items) if (!today.contains(i)) i];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // مصحفي الحر: سطر واحد.
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_outlined, size: 20, color: AppColors.navy),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.personalFreeMushaf, style: const TextStyle(fontWeight: FontWeight.w700))),
                    TextButton(onPressed: () => _openRead(), child: Text(t.personalContinueShort)),
                    TextButton(onPressed: q == null ? null : () => _goTo(q), child: Text(t.personalGoTo)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // تقرير أدائي.
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insights_outlined, color: AppColors.navy),
                  title: Text(t.personalReport, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PersonalReportScreen())),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(t.personalToday, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                  const Spacer(),
                  if (today.isNotEmpty)
                    Text(t.personalProgress(_ward.doneCount, today.length), style: TextStyle(fontSize: 12, color: AppColors.statusDone, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              if (_ward.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(t.personalEmpty, style: TextStyle(color: AppColors.textMuted, height: 1.7)),
                )
              else if (today.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.personalNoneToday, style: TextStyle(color: AppColors.textMuted)),
                ),
              for (final i in today)
                i.isKhatma
                    ? _KhatmaTile(item: i, quran: q, locale: locale, onOpen: () => _openItem(i), onOpenRange: _openKhatma)
                    : _ItemTile(item: i, title: personalItemTitle(t, i, q, _ward.adhkarCategories, en), locale: locale, onOpen: () => _openItem(i)),
              if (later.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(t.personalOffToday, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                for (final i in later)
                  i.isKhatma
                      ? _KhatmaTile(item: i, quran: q, locale: locale, onOpen: () => _openItem(i), onOpenRange: _openKhatma, dim: true)
                      : _ItemTile(item: i, title: personalItemTitle(t, i, q, _ward.adhkarCategories, en), locale: locale, onOpen: () => _openItem(i), dim: true),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: q == null ? null : () => _add(q),
                icon: const Icon(Icons.add),
                label: Text(t.personalAdd),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.title, required this.locale, required this.onOpen, this.dim = false});

  final PersonalItem item;
  final String title;
  final String locale;
  final VoidCallback onOpen;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ward = PersonalWard.instance;
    final done = !dim && ward.isDone(item);
    final auto = !dim && ward.autoDone(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: done ? AppColors.doneTint : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(3, 1, 4, 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: done ? AppColors.doneBorder : AppColors.border),
            ),
            child: Row(
              children: [
                // الدايرة: دوس عليها تعلّم أو تشيل "تم" بإيدك (الأذكار بتتعلّم لوحدها لما العدّاد يخلص).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: dim || auto ? null : () => ward.setDone(item, !done),
                  // مساحة لمس أكبر من الدايرة نفسها.
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? AppColors.statusDone : Colors.transparent,
                        border: Border.all(color: done ? AppColors.statusDone : AppColors.mutedLine, width: 2),
                      ),
                      child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: dim ? AppColors.textMuted : AppColors.text)),
                      Text(
                        [
                          auto ? t.personalAutoDone : _daysLabel(t, item, locale),
                          if (item.remindAt != null) t.personalRemindAt(_timeLabel(context, item.remindAt!)),
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (!done && !dim)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(99)),
                    child: Text(item.isSurah ? t.personalRead : t.personalOpen, style: TextStyle(fontSize: 11, color: AppColors.navy)),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'remove') return ward.remove(item.id);
                    if (v == 'remindOff') return ward.setRemind(item.id, null);
                    final m = await _pickRemindTime(context, item.remindAt);
                    if (m != null) await ward.setRemind(item.id, m);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'remind', child: Text(t.personalRemind)),
                    if (item.remindAt != null) PopupMenuItem(value: 'remindOff', child: Text(t.personalRemindOff)),
                    PopupMenuItem(value: 'remove', child: Text(t.personalRemove)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "انتقل إلى": سورة (من أولها)، أو جزء، أو سورة وآية. بيرجّع (سورة، آية).
/// بند الختمة: ورد النهارده وحدوده، وتقدّم الختمة، وتاريخ الختم، و"اقرأ ورد بكره".
class _KhatmaTile extends StatelessWidget {
  const _KhatmaTile({
    required this.item,
    required this.quran,
    required this.locale,
    required this.onOpen,
    required this.onOpenRange,
    this.dim = false,
  });

  final PersonalItem item;
  final QuranData? quran;
  final String locale;
  final VoidCallback onOpen;
  final Future<void> Function(int from, int to) onOpenRange;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ward = PersonalWard.instance;
    final k = item.khatma!;
    final en = locale == 'en';
    final today = ward.khatmaToday(item);
    final done = !dim && ward.isDone(item);
    final next = ward.khatmaNext(item);
    final eta = ward.khatmaEta(item);
    final q = quran;
    String where(int surah, int ayah) => '${q == null ? surah : (en ? q.surahNamesEn[surah - 1] : q.surahNamesAr[surah - 1].replaceFirst(RegExp(r'^سُوْرَةُ\s*'), ''))} $ayah';
    String? span;
    if (today != null && q != null) {
      final (s1, a1) = q.quarterStart(today.$1);
      final (s2, a2) = q.quarterEnd(today.$2);
      span = t.khatmaRangeSub(where(s1, a1), where(s2, a2));
    }
    final pct = (ward.khatmaProgress(item) * 100).round();
    final muted = TextStyle(fontSize: 11, color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: done ? AppColors.doneTint : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: today == null ? null : onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(3, 4, 4, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: done ? AppColors.doneBorder : AppColors.navy.withValues(alpha: 0.35), width: 1.3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: dim || today == null ? null : () => ward.setDone(item, !done),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done || k.finished ? AppColors.statusDone : Colors.transparent,
                            border: Border.all(color: done || k.finished ? AppColors.statusDone : AppColors.mutedLine, width: 2),
                          ),
                          child: done || k.finished ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(personalItemTitle(t, item, q, const [], en),
                              style: TextStyle(fontWeight: FontWeight.w700, color: dim ? AppColors.textMuted : AppColors.text)),
                          if (span != null) Text(span, style: muted),
                        ],
                      ),
                    ),
                    if (!done && !dim && today != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(99)),
                        child: Text(t.personalRead, style: TextStyle(fontSize: 11, color: AppColors.navy)),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'remove') return ward.remove(item.id);
                        if (v == 'restart') return ward.khatmaRestart(item);
                        if (v == 'remindOff') return ward.setRemind(item.id, null);
                        final m = await _pickRemindTime(context, item.remindAt);
                        if (m != null) await ward.setRemind(item.id, m);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'remind', child: Text(t.personalRemind)),
                        if (item.remindAt != null) PopupMenuItem(value: 'remindOff', child: Text(t.personalRemindOff)),
                        if (k.finished) PopupMenuItem(value: 'restart', child: Text(t.khatmaRestart)),
                        PopupMenuItem(value: 'remove', child: Text(t.personalRemove)),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      ProgressLine(value: k.finished ? 1 : ward.khatmaProgress(item)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: Text(t.khatmaProgressLine(pct, k.count + (k.finished ? 0 : 1)), style: muted)),
                          if (eta != null) Text(t.khatmaEta(DateFormat.MMMd(locale).format(eta)), style: muted),
                        ],
                      ),
                      if (k.finished && !dim)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: FilledButton.tonal(onPressed: () => ward.khatmaRestart(item), child: Text(t.khatmaRestart)),
                        )
                      else if (next != null && !dim)
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () => onOpenRange(next.$1, next.$2),
                          icon: const Icon(Icons.skip_next, size: 18),
                          label: Text(t.khatmaReadNext),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoToSheet extends StatefulWidget {
  const _GoToSheet({required this.quran});

  final QuranData quran;

  @override
  State<_GoToSheet> createState() => _GoToSheetState();
}

class _GoToSheetState extends State<_GoToSheet> {
  String _mode = 'surah'; // surah | juz | ayah
  String _q = '';
  int? _surah; // في وضع الآية: السورة اللي اخترتها
  final _ayah = TextEditingController();

  @override
  void dispose() {
    _ayah.dispose();
    super.dispose();
  }

  int? get _ayahValue {
    final s = _surah;
    final a = int.tryParse(_ayah.text.trim());
    if (s == null || a == null || a < 1 || a > widget.quran.ayahCount(s)) return null;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    final q = widget.quran;
    final names = en ? q.surahNamesEn : q.surahNamesAr;
    final key = normalizeArabic(_q.trim().toLowerCase());
    final shown = [
      for (var i = 0; i < names.length; i++)
        if (key.isEmpty || normalizeArabic(names[i].toLowerCase()).contains(key) || '${i + 1}' == key) i + 1,
    ];
    final picking = _mode != 'juz' && (_mode == 'surah' || _surah == null);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'surah', label: Text(t.personalTypeSurah)),
                  ButtonSegment(value: 'juz', label: Text(t.personalJuz)),
                  ButtonSegment(value: 'ayah', label: Text(t.personalAyah)),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() {
                  _mode = v.first;
                  _surah = null;
                  _ayah.clear();
                }),
              ),
            ),
            if (picking)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: InputDecoration(hintText: t.personalSearchSurah, prefixIcon: const Icon(Icons.search)),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            if (_mode == 'juz')
              Expanded(
                child: ListView(
                  children: [
                    for (var j = 1; j <= 30; j++)
                      Builder(builder: (context) {
                        final (s, a) = q.quarterStart((j - 1) * 8 + 1);
                        return ListTile(
                          leading: Text('$j', style: TextStyle(color: AppColors.textMuted)),
                          title: Text(t.juzLabel(j)),
                          subtitle: Text('${names[s - 1]} · $a'),
                          onTap: () => Navigator.pop(context, (s, a)),
                        );
                      }),
                  ],
                ),
              )
            else if (picking)
              Expanded(
                child: ListView(
                  children: [
                    for (final s in shown)
                      ListTile(
                        leading: Text('$s', style: TextStyle(color: AppColors.textMuted)),
                        title: Text(names[s - 1]),
                        trailing: _mode == 'ayah' ? const Icon(Icons.chevron_right) : null,
                        onTap: () => _mode == 'surah' ? Navigator.pop(context, (s, 1)) : setState(() => _surah = s),
                      ),
                  ],
                ),
              )
            else ...[
              // وضع الآية بعد اختيار السورة: رقم الآية.
              ListTile(
                title: Text(names[_surah! - 1], style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t.personalAyahRange(q.ayahCount(_surah!))),
                trailing: TextButton(onPressed: () => setState(() => _surah = null), child: Text(t.personalChange)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _ayah,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t.personalAyahNumber),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton(
                  onPressed: _ayahValue == null ? null : () => Navigator.pop(context, (_surah!, _ayahValue!)),
                  child: Text(t.personalGoTo),
                ),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.quran, required this.adhkar, this.khatma = false});

  final QuranData quran;
  final List<AdhkarCategory> adhkar;

  /// يفتح على "ختمة" على طول.
  final bool khatma;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  late String _type = widget.khatma ? 'khatma' : 'adhkar';

  // الختمة: المدة بالأيام أو ورد اليوم بالأرباع (واحدة بس)، والبداية، ولو فوّت يوم.
  int? _dur = 30;
  int? _perDay;
  int _startJuz = 1;
  bool _strict = false;
  final _durCtl = TextEditingController();

  @override
  void dispose() {
    _durCtl.dispose();
    super.dispose();
  }

  int get _startQ => (_startJuz - 1) * 8 + 1;

  /// أرباع كل يوم (من المدة أو من الاختيار).
  int? get _quartersPerDay {
    if (_perDay != null) return _perDay;
    final d = _dur;
    if (d == null || d <= 0) return null;
    return ((241 - _startQ) / d).ceil().clamp(1, 240);
  }

  /// تاريخ الختم المتوقع على الأيام المختارة.
  DateTime? get _eta {
    final per = _quartersPerDay;
    if (per == null) return null;
    var left = ((241 - _startQ) / per).ceil();
    final days = _chosenDays;
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    for (var g = 0; g < 4000; g++) {
      if (days.isEmpty || days.contains(d.weekday)) {
        left--;
        if (left <= 0) return d;
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return null;
  }

  Widget _khatmaForm(AppLocalizations t, String locale) {
    final label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted);
    final exists = PersonalWard.instance.khatmaItem != null;
    final per = _quartersPerDay;
    final eta = _eta;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exists)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(t.khatmaExists, style: TextStyle(color: AppColors.statusLate, height: 1.7)),
            ),
          const SizedBox(height: 12),
          Text(t.khatmaDuration, style: label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in [7, 10, 15, 30, 60])
                ChoiceChip(
                  label: Text(t.khatmaDaysChip(d)),
                  selected: _dur == d && _perDay == null,
                  onSelected: (_) => setState(() {
                    _dur = d;
                    _perDay = null;
                    _durCtl.clear();
                  }),
                ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _durCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(isDense: true, hintText: t.khatmaOtherDays),
                  onChanged: (v) => setState(() {
                    _dur = int.tryParse(v.trim());
                    _perDay = null;
                  }),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(child: Text(t.khatmaOr, style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
          ),
          Text(t.khatmaPerDayTitle, style: label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final n in [1, 4, 8, 16])
                ChoiceChip(
                  label: Text(khatmaAmount(t, n)),
                  selected: _perDay == n,
                  onSelected: (_) => setState(() {
                    _perDay = n;
                    _dur = null;
                    _durCtl.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(t.khatmaStartFrom, style: label),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: _startJuz,
            isDense: true,
            items: [for (var j = 1; j <= 30; j++) DropdownMenuItem(value: j, child: Text(t.juzLabel(j)))],
            onChanged: (v) => setState(() => _startJuz = v ?? 1),
          ),
          const SizedBox(height: 12),
          Text(t.khatmaMissed, style: label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(label: Text(t.khatmaWait), selected: !_strict, onSelected: (_) => setState(() => _strict = false)),
              ChoiceChip(label: Text(t.khatmaStrict), selected: _strict, onSelected: (_) => setState(() => _strict = true)),
            ],
          ),
          if (per != null && eta != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.doneTint,
                border: Border.all(color: AppColors.doneBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.khatmaPreview(khatmaAmount(t, per), DateFormat.yMMMd(locale).format(eta)),
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusDone)),
                  const SizedBox(height: 2),
                  Text(_strict ? t.khatmaPreviewStrict : t.khatmaPreviewWait, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  final _refs = <String>{};
  String _repeat = 'daily'; // daily | friday | custom
  final _days = <int>{};
  int? _remind;
  String _q = '';

  List<int> get _chosenDays => switch (_repeat) {
        'friday' => [DateTime.friday],
        'custom' => (_days.toList()..sort()),
        _ => const [],
      };

  bool get _canAdd =>
      (_type == 'khatma' ? (_quartersPerDay != null && PersonalWard.instance.khatmaItem == null) : _refs.isNotEmpty) &&
      (_repeat != 'custom' || _days.isNotEmpty);

  /// بند في القايمة: متعلّم لو اخترته، ومقفول بعلامة لو مضاف قبل كده.
  Widget _option(String ref, Widget title, {Widget? leading}) {
    final added = PersonalWard.instance.has(_type, ref);
    final on = added || _refs.contains(ref);
    return CheckboxListTile(
      value: on,
      enabled: !added,
      secondary: leading,
      title: title,
      controlAffinity: ListTileControlAffinity.trailing,
      onChanged: (v) => setState(() => v == true ? _refs.add(ref) : _refs.remove(ref)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final en = locale == 'en';
    final names = en ? widget.quran.surahNamesEn : widget.quran.surahNamesAr;
    final key = normalizeArabic(_q.trim().toLowerCase());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(t.personalAddTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'adhkar', label: Text(t.personalTypeAdhkar)),
                  ButtonSegment(value: 'surah', label: Text(t.personalTypeSurah)),
                  ButtonSegment(value: 'khatma', label: Text(t.personalTypeKhatma)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() {
                  _type = v.first;
                  _refs.clear();
                  _q = '';
                }),
              ),
            ),
            if (_type == 'surah')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  decoration: InputDecoration(hintText: t.personalSearchSurah, prefixIcon: const Icon(Icons.search)),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (_type == 'khatma')
                    _khatmaForm(t, locale)
                  else if (_type == 'adhkar')
                    for (final c in widget.adhkar)
                      _option(c.id, Text(en ? c.en : c.ar))
                  else
                    for (var i = 0; i < names.length; i++)
                      if (key.isEmpty || normalizeArabic(names[i].toLowerCase()).contains(key) || '${i + 1}' == key)
                        _option('${i + 1}', Text(names[i]), leading: Text('${i + 1}', style: TextStyle(color: AppColors.textMuted))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(t.personalRepeat, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: Text(t.personalEveryDay), selected: _repeat == 'daily', onSelected: (_) => setState(() => _repeat = 'daily')),
                  ChoiceChip(label: Text(t.personalFridayOnly), selected: _repeat == 'friday', onSelected: (_) => setState(() => _repeat = 'friday')),
                  ChoiceChip(label: Text(t.personalCustomDays), selected: _repeat == 'custom', onSelected: (_) => setState(() => _repeat = 'custom')),
                ],
              ),
            ),
            if (_repeat == 'custom')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(DateFormat.E(locale).format(DateTime(2023, 1, 1 + d))),
                        selected: _days.contains(d),
                        onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                      ),
                  ],
                ),
              ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(t.personalRemindToggle),
              subtitle: _remind == null ? null : Text(_timeLabel(context, _remind!)),
              value: _remind != null,
              onChanged: (v) async {
                if (!v) return setState(() => _remind = null);
                final m = await _pickRemindTime(context, _remind);
                if (m != null && mounted) setState(() => _remind = m);
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: !_canAdd
                        ? null
                        : () {
                            final base = DateTime.now().microsecondsSinceEpoch;
                            if (_type == 'khatma') {
                              final day = personalDayKey();
                              Navigator.pop(context, [
                                PersonalItem(
                                  id: '$base',
                                  type: 'khatma',
                                  ref: 'k',
                                  days: _chosenDays,
                                  since: day,
                                  remindAt: _remind,
                                  khatma: KhatmaPlan(perDay: _quartersPerDay!, start: _startQ, pos: _startQ, startedAt: day, strict: _strict),
                                ),
                              ]);
                              return;
                            }
                            // بالترتيب: أذكار بترتيب القايمة، والسور بترتيب المصحف.
                            final order = [for (final c in widget.adhkar) c.id];
                            final refs = _refs.toList()
                              ..sort((a, b) => _type == 'surah'
                                  ? int.parse(a).compareTo(int.parse(b))
                                  : order.indexOf(a).compareTo(order.indexOf(b)));
                            Navigator.pop(context, [
                              for (final (k, ref) in refs.indexed)
                                PersonalItem(id: '${base + k}', type: _type, ref: ref, days: _chosenDays, since: personalDayKey(), remindAt: _remind),
                            ]);
                          },
                    child: Text(_type == 'khatma' ? t.khatmaAdd : (_refs.isEmpty ? t.personalAdd : t.personalAddN(_refs.length))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
