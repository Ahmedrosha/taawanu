import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/auto_reader.dart';
import '../../theme/app_colors.dart';

/// شريط القراءة التلقائية: السابق والإيقاف والتالي، والسرعة − و+، والإغلاق.
class AutoReadBar extends StatelessWidget {
  const AutoReadBar({super.key, this.speedKey});

  /// مفتاح الجولة التعريفية لأزرار السرعة.
  final GlobalKey? speedKey;

  static String speedLabel(double s) {
    final v = s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString();
    return '×$v';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final auto = AutoReader.instance;
    final speed = auto.speed;
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 4),
          Expanded(
            child: Text(t.autoRead,
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          IconButton(tooltip: t.previousAyah, onPressed: auto.previous, icon: const Icon(Icons.skip_previous), visualDensity: VisualDensity.compact),
          IconButton.filled(
            tooltip: auto.playing ? t.pause : t.autoRead,
            onPressed: auto.waiting ? null : (auto.playing ? auto.pause : auto.resume),
            icon: Icon(auto.playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(tooltip: t.nextAyah, onPressed: auto.next, icon: const Icon(Icons.skip_next), visualDensity: VisualDensity.compact),
          Column(
            key: speedKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.ltr,
                children: [
                  _SpeedButton(icon: Icons.remove, onPressed: speed > AutoReader.speeds.first ? () => auto.changeSpeed(-1) : null),
                  SizedBox(
                    width: 38,
                    child: Text(speedLabel(speed), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  _SpeedButton(icon: Icons.add, onPressed: speed < AutoReader.speeds.last ? () => auto.changeSpeed(1) : null),
                ],
              ),
              Text(t.speed, style: TextStyle(fontSize: 10, color: AppColors.textMuted, height: 1)),
            ],
          ),
          IconButton(tooltip: t.stopAutoRead, onPressed: auto.stop, icon: const Icon(Icons.close), visualDensity: VisualDensity.compact),
        ],
      ),
    );
    if (!auto.waiting) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t.autoReadWaiting, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
        ),
        bar,
      ],
    );
  }
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 28,
        height: 28,
        child: IconButton.outlined(
          padding: EdgeInsets.zero,
          iconSize: 16,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      );
}
