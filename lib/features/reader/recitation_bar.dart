import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/prefs.dart';
import '../../services/recitation_player.dart';
import '../../theme/app_colors.dart';

/// شريط التلاوة تحت القارئ: القارئ، والسابق والتالي، والتشغيل، والتحميل، والإيقاف.
class RecitationBar extends StatelessWidget {
  const RecitationBar({super.key, required this.ayahs, required this.onRestart});

  /// الآيات اللي هتتحمّل (من الآية الحالية لآخر الربع).
  final List<(int, int)> Function() ayahs;

  /// إعادة التشغيل من الآية الحالية (بعد تغيير القارئ أو التكرار).
  final Future<void> Function({(int, int)? from}) onRestart;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final audio = RecitationPlayer.instance;
    final ar = Localizations.localeOf(context).languageCode != 'en';
    final r = audio.reciter;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _settings(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.record_voice_over_outlined, size: 18, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(ar ? r.nameAr : r.nameEn,
                          overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                    ),
                    if (audio.repeat != 1) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.repeat_one, size: 16, color: AppColors.accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(tooltip: t.previousAyah, onPressed: audio.previous, icon: const Icon(Icons.skip_previous), visualDensity: VisualDensity.compact),
          IconButton.filled(
            tooltip: audio.playing ? t.pause : t.listen,
            onPressed: audio.playing ? audio.pause : audio.resume,
            icon: Icon(audio.playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(tooltip: t.nextAyah, onPressed: audio.next, icon: const Icon(Icons.skip_next), visualDensity: VisualDensity.compact),
          ValueListenableBuilder<double?>(
            valueListenable: audio.downloadProgress,
            builder: (context, p, _) => p != null
                ? SizedBox(width: 40, height: 40, child: Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(value: p, strokeWidth: 2.5)))
                : IconButton(
                    tooltip: t.downloadPortionAudio,
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await audio.download(ayahs());
                      messenger.showSnackBar(SnackBar(content: Text(ok ? t.audioDownloaded : t.downloadFailed)));
                    },
                    icon: const Icon(Icons.download_for_offline_outlined),
                  ),
          ),
          IconButton(tooltip: t.stopRecitation, onPressed: audio.stop, icon: const Icon(Icons.close), visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }

  /// اختيار القارئ وعدد التكرار.
  Future<void> _settings(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final ar = Localizations.localeOf(context).languageCode != 'en';
    final audio = RecitationPlayer.instance;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Text(t.reciter, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              for (final r in RecitationPlayer.reciters)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Prefs.instance.reciterId == r.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: Prefs.instance.reciterId == r.id ? AppColors.navy : AppColors.textMuted,
                  ),
                  title: Text(ar ? r.nameAr : r.nameEn),
                  onTap: () async {
                    await Prefs.instance.setReciterId(r.id);
                    if (context.mounted) Navigator.pop(context, true);
                  },
                ),
              const SizedBox(height: 8),
              Text(t.repeatAyah, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in const [1, 3, 5, 0])
                    ChoiceChip(
                      label: Text(n == 0 ? t.repeatForever : t.repeatTimes(n)),
                      selected: audio.repeat == n,
                      showCheckmark: false,
                      selectedColor: AppColors.navy,
                      labelStyle: TextStyle(color: audio.repeat == n ? Colors.white : AppColors.text),
                      onSelected: (_) async {
                        await Prefs.instance.setRecitationRepeat(n);
                        if (context.mounted) Navigator.pop(context, true);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (changed == true) await onRestart(from: audio.current);
  }
}
