import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/personal_ward.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../adhkar/adhkar_data.dart';
import '../adhkar/adhkar_screen.dart' show DhikrListScreen;
import '../groups/group_board_screen.dart' show ReadRequest;

/// اسم البند: القسم بالعربي أو الإنجليزي، أو اسم السورة.
String personalItemTitle(AppLocalizations t, PersonalItem i, QuranData? q, List<AdhkarCategory> adhkar, bool en) {
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
    final cat = _ward.adhkarCategories.where((c) => c.id == i.ref).firstOrNull;
    if (cat == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DhikrListScreen(title: personalItemTitle(t, i, null, _ward.adhkarCategories, en), sections: [cat]),
    ));
    if (mounted) setState(() {});
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

  Future<void> _add(QuranData q) async {
    final items = await showModalBottomSheet<List<PersonalItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddSheet(quran: q, adhkar: _ward.adhkarCategories),
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
              for (final i in today) _ItemTile(item: i, title: personalItemTitle(t, i, q, _ward.adhkarCategories, en), locale: locale, onOpen: () => _openItem(i)),
              if (later.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(t.personalOffToday, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                for (final i in later) _ItemTile(item: i, title: personalItemTitle(t, i, q, _ward.adhkarCategories, en), locale: locale, onOpen: () => _openItem(i), dim: true),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: done ? AppColors.doneBorder : AppColors.border),
            ),
            child: Row(
              children: [
                // الدايرة: دوس عليها تعلّم أو تشيل "تم" بإيدك (الأذكار بتتعلّم لوحدها لما العدّاد يخلص).
                GestureDetector(
                  onTap: dim || auto ? null : () => ward.setDone(item, !done),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: dim ? AppColors.textMuted : AppColors.text)),
                      Text(auto ? t.personalAutoDone : _daysLabel(t, item, locale), style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
                  onSelected: (_) => ward.remove(item.id),
                  itemBuilder: (_) => [PopupMenuItem(value: 'remove', child: Text(t.personalRemove))],
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
  const _AddSheet({required this.quran, required this.adhkar});

  final QuranData quran;
  final List<AdhkarCategory> adhkar;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  String _type = 'adhkar';
  final _refs = <String>{};
  String _repeat = 'daily'; // daily | friday | custom
  final _days = <int>{};
  String _q = '';

  List<int> get _chosenDays => switch (_repeat) {
        'friday' => [DateTime.friday],
        'custom' => (_days.toList()..sort()),
        _ => const [],
      };

  bool get _canAdd => _refs.isNotEmpty && (_repeat != 'custom' || _days.isNotEmpty);

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
                  if (_type == 'adhkar')
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
                            // بالترتيب: أذكار بترتيب القايمة، والسور بترتيب المصحف.
                            final order = [for (final c in widget.adhkar) c.id];
                            final refs = _refs.toList()
                              ..sort((a, b) => _type == 'surah'
                                  ? int.parse(a).compareTo(int.parse(b))
                                  : order.indexOf(a).compareTo(order.indexOf(b)));
                            Navigator.pop(context, [
                              for (final (k, ref) in refs.indexed)
                                PersonalItem(id: '${base + k}', type: _type, ref: ref, days: _chosenDays, since: personalDayKey()),
                            ]);
                          },
                    child: Text(_refs.isEmpty ? t.personalAdd : t.personalAddN(_refs.length)),
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
