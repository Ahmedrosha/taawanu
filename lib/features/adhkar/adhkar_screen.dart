import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../widgets/placeholder_view.dart';

class AdhkarScreen extends StatelessWidget {
  const AdhkarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderView(title: AppLocalizations.of(context).tabAdhkar);
  }
}
