import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../widgets/placeholder_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderView(title: AppLocalizations.of(context).greeting);
  }
}
