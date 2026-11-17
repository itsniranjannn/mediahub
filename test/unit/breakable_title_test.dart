import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/utils/formatters.dart';

void main() {
  test('breakableTitle adds a wrap point after each underscore only', () {
    expect(breakableTitle('Sunrise Over Phewa Lake'), 'Sunrise Over Phewa Lake');
    expect(breakableTitle('Audit_Long_Tone_5min'), 'Audit_​Long_​Tone_​5min');
    expect(breakableTitle('a__b'), 'a_​_​b');
    expect(breakableTitle(''), '');
    // the visible characters are unchanged
    expect(breakableTitle('गीत_नेपाली_audit').replaceAll('​', ''), 'गीत_नेपाली_audit');
  });
}
