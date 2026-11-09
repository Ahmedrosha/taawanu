import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../theme/app_colors.dart';

/// ذكر في السبحة: النص والعدد المطلوب في الدورة.
class _Tasbeeh {
  const _Tasbeeh(this.id, this.ar, this.en, this.target, {this.custom = false});
  final String id;
  final String ar;
  final String en;
  final int target;
  final bool custom;
}

const _presets = [
  _Tasbeeh('subhan', 'سُبْحَانَ اللَّهِ', 'Subhan Allah', 33),
  _Tasbeeh('hamd', 'الْحَمْدُ لِلَّهِ', 'Alhamdulillah', 33),
  _Tasbeeh('akbar', 'اللَّهُ أَكْبَرُ', 'Allahu Akbar', 34),
  _Tasbeeh('istighfar', 'أَسْتَغْفِرُ اللَّهَ', 'Astaghfirullah', 100),
  _Tasbeeh('tahlil', 'لَا إِلَهَ إِلَّا اللَّهُ', 'La ilaha illa Allah', 100),
  _Tasbeeh('salah', 'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ', 'Salawat upon the Prophet ﷺ', 100),
  _Tasbeeh('subhanbihamdih', 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ', 'Subhan Allahi wa bihamdih', 100),
];

/// السبحة: دوسة في أي مكان تعد، وهزة مع كل عدة وهزة أقوى مع تمام العدد.
class TasbeehScreen extends StatefulWidget {
  const TasbeehScreen({super.key});

  @override
  State<TasbeehScreen> createState() => _TasbeehScreenState();
}

class _TasbeehScreenState extends State<TasbeehScreen> {
  static String _dayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  String _today = _dayKey();
  late Map<String, int> _counts = Prefs.instance.tasbeehCounts(_today);
  late List<(String, int)> _custom = Prefs.instance.tasbeehCustom;
  late String _sel = Prefs.instance.tasbeehSelected ?? _presets.first.id;

  List<_Tasbeeh> get _all => [
        ..._presets,
        for (var i = 0; i < _custom.length; i++) _Tasbeeh('c$i', _custom[i].$1, _custom[i].$1, _custom[i].$2, custom: true),
      ];

  _Tasbeeh get _current => _all.firstWhere((x) => x.id == _sel, orElse: () => _presets.first);

  int get _total => _counts.values.fold(0, (a, b) => a + b);

  void _rollDay() {
    final d = _dayKey();
    if (d != _today) {
      _today = d;
      _counts = {};
    }
  }

  void _save() => Prefs.instance.setTasbeehCounts(_today, _counts);

  void _tap() {
    _rollDay();
    final x = _current;
    final c = (_counts[x.id] ?? 0) + 1;
    setState(() => _counts[x.id] = c);
    if (c % x.target == 0) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    _save();
  }

  void _undo() {
    final c = _counts[_current.id] ?? 0;
    if (c == 0) return;
    setState(() => _counts[_current.id] = c - 1);
    _save();
  }

  void _reset() {
    setState(() => _counts.remove(_current.id));
    _save();
  }

  void _select(String id) {
    setState(() => _sel = id);
    Prefs.instance.setTasbeehSelected(id);
  }

  Future<void> _addCustom() async {
    final t = AppLocalizations.of(context);
    final text = TextEditingController();
    final target = TextEditingController(text: '33');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.tasbeehAdd),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: text, autofocus: true, maxLength: 80, decoration: InputDecoration(labelText: t.tasbeehText)),
            TextField(
              controller: target,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: InputDecoration(labelText: t.tasbeehTarget),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.save)),
        ],
      ),
    );
    final name = text.text.trim().replaceAll('|', ' ');
    final n = int.tryParse(target.text) ?? 0;
    text.dispose();
    target.dispose();
    if (ok != true || name.isEmpty || n <= 0) return;
    setState(() => _custom = [..._custom, (name, n)]);
    await Prefs.instance.setTasbeehCustom(_custom);
    _select('c${_custom.length - 1}');
  }

  Future<void> _removeCustom(_Tasbeeh x) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.tasbeehRemove),
        content: Text(x.ar),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.tasbeehDelete)),
        ],
      ),
    );
    if (ok != true) return;
    final i = int.parse(x.id.substring(1));
    // الأذكار اللي بعده بتتزحزح، فعدّاداتها بتتنقل معاها.
    final moved = <String, int>{};
    _counts.forEach((k, v) {
      if (!k.startsWith('c')) {
        moved[k] = v;
      } else {
        final j = int.tryParse(k.substring(1)) ?? -1;
        if (j < i) moved[k] = v;
        if (j > i) moved['c${j - 1}'] = v;
      }
    });
    setState(() {
      _custom = [..._custom]..removeAt(i);
      _counts = moved;
      if (_sel == x.id) _sel = _presets.first.id;
    });
    await Prefs.instance.setTasbeehCustom(_custom);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    _rollDay();
    final x = _current;
    final c = _counts[x.id] ?? 0;
    final inRound = c % x.target;
    final rounds = c ~/ x.target;
    final shown = c > 0 && inRound == 0 ? x.target : inRound;
    final progress = shown / x.target;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tasbeeh, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: t.undo, onPressed: c == 0 ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: t.reset, onPressed: c == 0 ? null : _reset, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final d in _all)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: GestureDetector(
                      onLongPress: d.custom ? () => _removeCustom(d) : null,
                      child: ChoiceChip(
                        label: Text(en && !d.custom ? d.en : d.ar),
                        selected: d.id == x.id,
                        showCheckmark: false,
                        selectedColor: AppColors.navy,
                        labelStyle: TextStyle(color: d.id == x.id ? Colors.white : AppColors.text),
                        onSelected: (_) => _select(d.id),
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: Icon(Icons.add, size: 18, color: AppColors.accent),
                  label: Text(t.tasbeehAdd),
                  onPressed: _addCustom,
                ),
              ],
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _tap,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        x.ar,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: 'KFGQPC Hafs', fontSize: 30, height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 10,
                              backgroundColor: AppColors.navy.withValues(alpha: 0.15),
                              color: c > 0 && inRound == 0 ? AppColors.statusDone : AppColors.accent,
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$shown', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700)),
                                  Text('/ ${x.target}', style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (rounds > 0) Text(t.tasbeehRounds(rounds), style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      Text(t.tapAnywhereToCount, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(t.tasbeehToday(_total), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
