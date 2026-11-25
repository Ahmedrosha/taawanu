import 'package:flutter/widgets.dart';

import '../l10n/digits.dart';

/// الرقم (أو الكلام اللي فيه أرقام) بأرقام لغة التطبيق: عربي في العربي.
extension LocalDigits on BuildContext {
  String digits(Object v) => localDigits(Localizations.localeOf(this).languageCode, v);
}
