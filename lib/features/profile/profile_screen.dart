import 'package:flutter/material.dart';

import '../../app.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../widgets/placeholder_view.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = AuthService.instance.user;
    return PlaceholderView(
      title: t.tabProfile,
      child: Column(
        children: [
          if (user != null) ...[
            Text(user.displayName ?? t.defaultUserName, style: Theme.of(context).textTheme.titleLarge),
            if (user.email != null)
              Text(user.email!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
          ],
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
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () => AuthService.instance.signOut(),
            icon: const Icon(Icons.logout),
            label: Text(t.signOut),
          ),
        ],
      ),
    );
  }
}
