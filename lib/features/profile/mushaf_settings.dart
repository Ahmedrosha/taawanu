import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/mushaf_fonts.dart';
import '../reader/mushaf_page.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/highlight_colors.dart';
import '../../widgets/quran_style.dart';
import '../../widgets/ui.dart';

/// إعدادات المصحف في "حسابي": شكل القراءة (صفحات أو نص متصل)، وخط الصفحات،
/// وحجم ونوع خط النص المتصل مع معاينة.
class MushafSettings extends StatefulWidget {
  const MushafSettings({super.key});

  @override
  State<MushafSettings> createState() => _MushafSettingsState();
}

class _MushafSettingsState extends State<MushafSettings> {
  late double _size = Prefs.instance.readerFontSize;
  late String _font = Prefs.instance.readerFont;
  late String _highlight = Prefs.instance.highlightColor;

  String _colorName(AppLocalizations t, String id) => switch (id) {
        'yellow' => t.colorYellow,
        'green' => t.colorGreen,
        'blue' => t.colorBlue,
        'pink' => t.colorPink,
        _ => t.colorGold,
      };
  late String _view = Prefs.instance.readerView;
  late String _style = Prefs.instance.pageStyle;

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.navy,
        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.text),
        onSelected: (_) => onTap(),
      );

  String _fontName(AppLocalizations t, String f) => switch (f) {
        madinahFont => t.fontMadinah,
        'Amiri Quran' => t.fontAmiriQuran,
        'Scheherazade New' => t.fontScheherazade,
        'Amiri' => t.fontAmiri,
        _ => t.fontNaskh,
      };

  void _setView(String v) {
    setState(() => _view = v);
    Prefs.instance.setReaderView(v);
  }

  /// اختيار من "شكل القراءة": دايرة واسم، وتحته إعداداته.
  Widget _option({required String value, required String label, bool isDefault = false, required List<Widget> children}) {
    final t = AppLocalizations.of(context);
    final selected = _view == value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _setView(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? AppColors.navy : AppColors.textMuted),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(6)),
                    child: Text(t.defaultTag, style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 34),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text);
    final note = TextStyle(fontSize: 12, color: AppColors.textMuted);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.readingView, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _option(
            value: 'pages',
            label: t.viewPages,
            isDefault: true,
            children: [
              // عينة من شكل الصفحة بالخط المختار.
              MushafSample(qpc: _style != 'hafs', key: ValueKey(_style)),
              const SizedBox(height: 10),
              Text(t.pageStyle, style: label),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip(t.pageStyleHafs, _style == 'hafs', () {
                  setState(() => _style = 'hafs');
                  Prefs.instance.setPageStyle('hafs');
                }),
                _chip(t.pageStyleQpc, _style == 'qpc', () {
                  setState(() => _style = 'qpc');
                  Prefs.instance.setPageStyle('qpc');
                }),
                _chip(t.pageStyleTajweed, _style == 'tajweed', () {
                  setState(() => _style = 'tajweed');
                  Prefs.instance.setPageStyle('tajweed');
                }),
              ]),
              const SizedBox(height: 8),
              Text(_style == 'hafs' ? t.pagesNote : t.qpcNote, style: note),
              if (_style == 'tajweed') ...[
                const SizedBox(height: 10),
                const TajweedLegend(),
                const SizedBox(height: 6),
                Text(t.tajweedCredit, style: note),
              ],
              if (_style != 'hafs') _QpcDownloads(key: ValueKey(_style)),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.border),
          _option(
            value: 'text',
            label: t.viewText,
            children: [
              // معاينة: آية بالخط والحجم المختارين.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(12)),
                child: FutureBuilder<QuranData>(
                  // المفتاح بالخط: لما الخط يتغير، النص يتحمّل من جديد (مصحف المدينة نصه مختلف).
                  key: ValueKey(_font),
                  future: QuranRepository.instance.loadFor(_font),
                  builder: (context, snap) => Text(
                    snap.data?.ayahText(1, 2) ?? '',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: quranTextStyle(_font, fontSize: _size, color: AppColors.text),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(t.textSize, style: label),
              Slider(
                value: _size,
                min: 18,
                max: 40,
                divisions: 11,
                label: _size.round().toString(),
                onChanged: (v) => setState(() => _size = v),
                onChangeEnd: (v) => Prefs.instance.setReaderFontSize(v),
              ),
              Text(t.fontType, style: label),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in Prefs.readerFonts)
                    _chip(_fontName(t, f), _font == f, () {
                      setState(() => _font = f);
                      Prefs.instance.setReaderFont(f);
                    }),
                ],
              ),
              const SizedBox(height: 10),
              Text(t.textViewOnlyNote, style: note),
              const SizedBox(height: 4),
              Text(_font == madinahFont ? t.quranTextSourceMadinah : t.quranTextSource, style: note),
            ],
          ),
          const SizedBox(height: 16),
          // لون تظليل الآية أو الكلمة وقت التلاوة والقراءة الصامتة.
          Text(t.highlightColor, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final id in highlightPalette.keys)
                Semantics(
                  button: true,
                  selected: _highlight == id,
                  label: _colorName(t, id),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() => _highlight = id);
                      Prefs.instance.setHighlightColor(id);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: highlightColorFor(id),
                        shape: BoxShape.circle,
                        border: Border.all(color: _highlight == id ? AppColors.accent : AppColors.border, width: _highlight == id ? 3 : 1),
                      ),
                      child: _highlight == id ? Icon(Icons.check, size: 20, color: AppColors.text) : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // معاينة: كلمة منوّرة وسط الكلام.
          Text.rich(
            TextSpan(
              style: quranTextStyle(_font, fontSize: 22, color: AppColors.text),
              children: [
                const TextSpan(text: 'ٱلۡحَمۡدُ لِلَّهِ '),
                TextSpan(text: 'رَبِّ ٱلۡعَٰلَمِينَ', style: TextStyle(backgroundColor: highlightColorFor(_highlight))),
              ],
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}

/// تحميل كل صفحات خطوط المجمع مرة واحدة، أو مسحها.
class _QpcDownloads extends StatefulWidget {
  const _QpcDownloads({super.key});

  @override
  State<_QpcDownloads> createState() => _QpcDownloadsState();
}

class _QpcDownloadsState extends State<_QpcDownloads> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await MushafFonts.instance.downloadedCount();
    if (mounted) setState(() => _count = n);
  }

  Future<void> _downloadAll() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await MushafFonts.instance.downloadAll();
    await _refresh();
    if (!ok && (_count ?? 0) < 604) messenger.showSnackBar(SnackBar(content: Text(t.downloadFailed)));
  }

  Future<void> _delete() async {
    await MushafFonts.instance.deleteAll();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final fonts = MushafFonts.instance;
    return ValueListenableBuilder<double?>(
      valueListenable: fonts.progress,
      builder: (context, p, _) {
        if (p != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(value: p),
                      const SizedBox(height: 4),
                      Text(t.downloadingPages((p * 100).round()), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                TextButton(onPressed: fonts.cancelDownload, child: Text(t.cancel)),
              ],
            ),
          );
        }
        final n = _count ?? 0;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(t.pagesDownloaded(n), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              if (n < 604)
                TextButton.icon(onPressed: _downloadAll, icon: const Icon(Icons.download, size: 18), label: Text(t.downloadAllPages)),
              if (n > 0)
                TextButton(onPressed: _delete, child: Text(t.deleteDownloadedPages)),
            ],
          ),
        );
      },
    );
  }
}

/// ألوان التجويد في مصحف المجمع الملون.
class TajweedLegend extends StatelessWidget {
  const TajweedLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      (const Color(0xFF9B1B1B), t.tjMaddLazim),
      (const Color(0xFFE0262B), t.tjMaddWajib),
      (const Color(0xFFF08A24), t.tjMaddJaiz),
      (const Color(0xFFC9A227), t.tjMaddTabii),
      (const Color(0xFF169C3B), t.tjGhunnah),
      (const Color(0xFF2E9BD6), t.tjQalqalah),
      (const Color(0xFF1F3F9E), t.tjTafkhim),
      (const Color(0xFF9AA0A6), t.tjSilent),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.tajweedColors, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final (c, label) in items)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
              ]),
          ],
        ),
      ],
    );
  }
}
