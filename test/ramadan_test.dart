import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/features/prayer/prayer_controller.dart';

void main() {
  test('رمضان ١٤٤٨ (فبراير ٢٠٢٧ تقريبًا) حسب أم القرى', () {
    expect(PrayerController.isRamadan(DateTime(2027, 2, 20)), isTrue);
    expect(PrayerController.isRamadan(DateTime(2026, 10, 31)), isFalse);
  });
}
