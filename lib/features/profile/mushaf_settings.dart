import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/mushaf_fonts.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.readingView, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(t.viewPages, _view == 'pages', () {
              setState(() => _view = 'pages');
              Prefs.instance.setReaderView('pages');
            }),
            _chip(t.viewText, _view == 'text', () {
              setState(() => _view = 'text');
              Prefs.instance.setReaderView('text');
            }),
          ]),
          const SizedBox(height: 14),
          Text(t.pageStyle, style: const TextStyle(fontWeight: FontWeight.w600)),
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
          ]),
          const SizedBox(height: 8),
          Text(_style == 'qpc' ? t.qpcNote : t.pagesNote, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          if (_style == 'qpc') const _QpcDownloads(),
          const SizedBox(height: 14),
          Divider(color: AppColors.border),
          const SizedBox(height: 8),
          Text(t.textViewSettings, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          // معاينة: آية من الفاتحة بالخط والحجم المختارين.
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
          Text(t.textSize, style: const TextStyle(fontWeight: FontWeight.w600)),
          Slider(
            value: _size,
            min: 18,
            max: 40,
            divisions: 11,
            label: _size.round().toString(),
            onChanged: (v) => setState(() => _size = v),
            onChangeEnd: (v) => Prefs.instance.setReaderFontSize(v),
          ),
          Text(t.fontType, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in Prefs.readerFonts)
                ChoiceChip(
                  label: Text(_fontName(t, f)),
                  selected: _font == f,
                  showCheckmark: false,
                  selectedColor: AppColors.navy,
                  labelStyle: TextStyle(color: _font == f ? Colors.white : AppColors.text),
                  onSelected: (_) {
                    setState(() => _font = f);
                    Prefs.instance.setReaderFont(f);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_font == madinahFont ? t.quranTextSourceMadinah : t.quranTextSource,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// تحميل كل صفحات خطوط المجمع مرة واحدة، أو مسحها.
class _QpcDownloads extends StatefulWidget {
  const _QpcDownloads();

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
