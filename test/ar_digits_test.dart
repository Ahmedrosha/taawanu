import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/l10n/ar_digits.dart';
import 'package:taawanu/l10n/digits.dart';
import 'package:flutter/widgets.dart';

void main() {
  test('arDigits', () {
    expect(arDigits('متحمّل 604 من ٦٠٤'), 'متحمّل ٦٠٤ من ٦٠٤');
    expect(arDigits('84% · 6.4 · 12,345'), '٨٤٪ · ٦٫٤ · ١٢٬٣٤٥');
    expect(localDigits('en', 604), '604');
  });

  test('Arabic localizations use Arabic digits, English unchanged', () {
    final ar = lookupLocalized(const Locale('ar'));
    final en = lookupLocalized(const Locale('en'));
    expect(ar.earnedPoints(50).contains('٥٠'), isTrue);
    expect(RegExp(r'[0-9]').hasMatch(ar.earnedPoints(50)), isFalse);
    expect(en.earnedPoints(50).contains('50'), isTrue);
    expect(ar.appVersion('1.0.42', '72').contains('1.0.42'), isTrue);
  });
}
