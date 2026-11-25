/// أرقام عربي (٠١٢٣…) للكلام العربي، و٪ و٫ و٬ بدل % و. و, في الأرقام.
String arDigits(String s) => s
    .replaceAllMapped(RegExp(r'(?<=\d)\.(?=\d)'), (_) => '٫')
    .replaceAllMapped(RegExp(r'(?<=\d),(?=\d{3})'), (_) => '٬')
    .replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)])
    .replaceAll('%', '٪');

/// الرقم بأرقام اللغة: عربي في العربي، وزي ما هو في الإنجليزي.
String localDigits(String languageCode, Object n) => languageCode == 'ar' ? arDigits('$n') : '$n';
