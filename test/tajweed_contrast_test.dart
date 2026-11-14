import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/theme/highlight_colors.dart';
import 'package:taawanu/theme/tajweed_colors.dart';

import 'package:flutter/material.dart';

/// كل لون تجويد، فوق الصفحة وفوق كل ألوان التظليل، في الوضع الفاتح والغامق، لازم يبان (تباين ٣ على الأقل).
void main() {
  const papers = {false: Color(0xFFFFFDF7), true: Color(0xFF16140F)};
  const texts = {false: Color(0xFF0F172A), true: Color(0xFFE6EDF7)};
  for (final dark in [false, true]) {
    final bgs = <String, Color>{
      'paper': papers[dark]!,
      for (final e in highlightPalette.entries) e.key: dark ? e.value.$2 : e.value.$1,
    };
    for (final bg in bgs.entries) {
      test('${dark ? 'dark' : 'light'} on ${bg.key}', () {
        for (final (k, c) in tajweedPalette(dark: dark).indexed) {
          final out = readableOn(c, bg.value);
          expect(contrastRatio(out, bg.value), greaterThanOrEqualTo(3.0), reason: 'kind $k');
        }
        final txt = readableOn(texts[dark]!, bg.value, min: 4.5);
        expect(contrastRatio(txt, bg.value), greaterThanOrEqualTo(4.5), reason: 'text');
      });
    }
  }
}
