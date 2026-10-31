import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/quran_style.dart';
import '../../widgets/ui.dart';

/// إعدادات المصحف في "حسابي": حجم الخط ونوعه، مع معاينة.
class MushafSettings extends StatefulWidget {
  const MushafSettings({super.key});

  @override
  State<MushafSettings> createState() => _MushafSettingsState();
}

class _MushafSettingsState extends State<MushafSettings> {
  late double _size = Prefs.instance.readerFontSize;
  late String _font = Prefs.instance.readerFont;

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
