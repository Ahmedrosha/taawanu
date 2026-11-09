import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/features/zakat/zakat_calc.dart';

void main() {
  test('الزكاة ٢.٥٪ لما المال يوصل النصاب', () {
    final d = ZakatData(values: {'cash': 500000, 'gold21': 80, 'debts': 20000});
    final r = computeZakat(d, 7000, 90);
    // ٨٠ جم عيار ٢١ = ٧٠ جم عيار ٢٤ = ٤٩٠ ألف
    expect(r.goldValue, closeTo(490000, 0.01));
    expect(r.total, closeTo(970000, 0.01));
    expect(r.nisab, 85 * 7000);
    expect(r.due, closeTo(24250, 0.01));
  });

  test('أقل من النصاب: مفيش زكاة', () {
    final r = computeZakat(ZakatData(values: {'cash': 100000}), 7000, 90);
    expect(r.reached, isFalse);
    expect(r.due, 0);
  });

  test('الحلي الملبوس مش بيتحسب غير لو اختاره', () {
    final d = ZakatData(values: {'jewelry21': 24});
    expect(computeZakat(d, 1000, 10).goldValue, 0);
    d.includeJewelry = true;
    expect(computeZakat(d, 1000, 10).goldValue, closeTo(21000, 0.01));
  });

  test('الحول بعد سنة هجرية (حوالي ٣٥٤ يوم)', () {
    final start = DateTime(2025, 11, 10);
    final h = nextHawl(start, DateTime(2025, 11, 11));
    final days = h.difference(start).inDays;
    expect(days, inInclusiveRange(353, 356));
  });
}
