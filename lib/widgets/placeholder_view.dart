import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/app_colors.dart';

/// شاشة مؤقتة لحد ما نبني الشاشة الحقيقية.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.title, this.child});

  final String title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.comingSoon, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textMuted)),
              if (child != null) ...[const SizedBox(height: 24), child!],
            ],
          ),
        ),
      ),
    );
  }
}
