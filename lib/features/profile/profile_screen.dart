import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../widgets/placeholder_view.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PlaceholderView(
      title: t.tabProfile,
      child: Column(
        children: [
          Text(t.language, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ValueListenableBuilder<Locale>(
            valueListenable: localeNotifier,
            builder: (context, locale, _) => SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'ar', label: Text(t.arabic)),
                ButtonSegment(value: 'en', label: Text(t.english)),
              ],
              selected: {locale.languageCode},
              onSelectionChanged: (s) => localeNotifier.value = Locale(s.first),
            ),
          ),
        ],
      ),
    );
  }
}
