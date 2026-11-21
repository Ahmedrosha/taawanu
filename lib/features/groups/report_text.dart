/// أرقام عربي (٠١٢٣…) للتقارير والرسايل العربي، و٪ و٫ بدل % و. في الأرقام.
String arDigits(String s) => s
    .replaceAllMapped(RegExp(r'(?<=\d)\.(?=\d)'), (_) => '٫')
    .replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)])
    .replaceAll('%', '٪');

/// علامة اتجاه مخفية (RLM) في أول كل سطر: الواتس اب بيعرض السطر يمين لشمال حتى لو بادئ باسم إنجليزي.
String rtlLines(String s) => s.split('\n').map((l) => l.isEmpty ? l : '‏$l').join('\n');
