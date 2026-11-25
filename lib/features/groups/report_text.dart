export '../../l10n/digits.dart' show arDigits;

/// علامة اتجاه مخفية (RLM) في أول كل سطر: الواتس اب بيعرض السطر يمين لشمال حتى لو بادئ باسم إنجليزي.
String rtlLines(String s) => s.split('\n').map((l) => l.isEmpty ? l : '‏$l').join('\n');
