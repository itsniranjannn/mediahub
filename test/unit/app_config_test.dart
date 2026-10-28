import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/app_config.dart';

void main() {
  test('AppConfig.appName is correct', () {
    expect(AppConfig.appName, equals('MediaHub'));
  });
}
