// مؤقت: قياس عرض المسافة والكلمات في خطوط المجمع V2 و V4 (صفحة ٢٩).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('space', () async {
    final d = jsonDecode(File('assets/mushaf/pages.json').readAsStringSync()) as Map<String, dynamic>;
    final lines = (d['pages'] as List)[28] as List;
    for (final v in ['v2', 'v4']) {
      final l = FontLoader(v)..addFont(Future.value(ByteData.sublistView(File('build/$v.ttf').readAsBytesSync())));
      await l.load();
      double w(String s) {
        final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontFamily: v, fontSize: 40, height: 1.0)), textDirection: TextDirection.rtl, maxLines: 1)..layout();
        return tp.width;
      }

      for (final ln in lines.take(4)) {
        if (ln[0] != 't') continue;
        final words = [for (final x in ln[1] as List) x[3] as String];
        final joined = w(words.join(' '));
        final sum = words.fold<double>(0, (a, x) => a + w(x));
        // ignore: avoid_print
        print('$v words=${words.length} joined=${joined.toStringAsFixed(1)} sum=${sum.toStringAsFixed(1)} space=${w(' ').toStringAsFixed(1)} perGap=${((joined - sum) / (words.length - 1)).toStringAsFixed(1)}');
      }
    }
  });
}
