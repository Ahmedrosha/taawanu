import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import 'prayer_controller.dart';
import 'prayer_screen.dart' show formatTime, prayerName, timeUntil;

/// كارت الرئيسية: الصلاة الجاية، والضغط عليه بيفتح تبويب الصلاة.
class NextPrayerTile extends StatefulWidget {
  const NextPrayerTile({super.key});

  @override
  State<NextPrayerTile> createState() => _NextPrayerTileState();
}

class _NextPrayerTileState extends State<NextPrayerTile> {
  final _c = PrayerController.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _c.addListener(_refresh);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final Widget content;
    if (!_c.hasLocation) {
      content = Text(t.setupPrayerTimes, style: const TextStyle(fontWeight: FontWeight.w600));
    } else {
      final now = DateTime.now();
      final (p, at) = _c.next(now);
      content = Text.rich(
        TextSpan(children: [
          TextSpan(text: '${t.nextPrayer}: ', style: TextStyle(color: AppColors.textMuted)),
          TextSpan(text: '${prayerName(t, p)} ${formatTime(context, at)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' · ${timeUntil(t, at.difference(now.toUtc()))}', style: TextStyle(color: AppColors.textMuted)),
        ]),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go('/prayer'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.mosque_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: content),
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
