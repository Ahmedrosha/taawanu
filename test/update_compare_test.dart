import 'package:flutter_test/flutter_test.dart';
import 'package:taawanu/services/update_service.dart';

void main() {
  test('مقارنة أرقام النسخ', () {
    expect(UpdateService.compare('1.0.17', '1.0.18'), -1);
    expect(UpdateService.compare('1.0.18', '1.0.18'), 0);
    expect(UpdateService.compare('1.0.18+3', '1.0.18'), 0);
    expect(UpdateService.compare('1.1.0', '1.0.99'), 1);
    expect(UpdateService.compare('1.0.9', '1.0.10'), -1);
  });
}
