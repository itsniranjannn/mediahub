import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/utils/formatters.dart';

void main() {
  test('formatClock drops the leading zero of the first group', () {
    expect(formatClock(Duration.zero), '0:00');
    expect(formatClock(const Duration(minutes: 4, seconds: 5)), '4:05');
    expect(formatClock(const Duration(minutes: 12, seconds: 30)), '12:30');
    expect(formatClock(const Duration(minutes: 58, seconds: 12)), '58:12');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatClock(const Duration(hours: 10, minutes: 4, seconds: 5)), '10:04:05');
    expect(formatClock(const Duration(seconds: -3)), '0:00');
    expect(formatClock(const Duration(hours: -2)), '0:00');
    expect(formatClock(const Duration(minutes: 9, seconds: 59)), '9:59');
    expect(formatClock(const Duration(minutes: 10)), '10:00');
    expect(formatClock(const Duration(minutes: 59, seconds: 59, milliseconds: 999)), '59:59');
    expect(formatClock(const Duration(hours: 1)), '1:00:00');
    expect(formatClock(const Duration(hours: 9, minutes: 59, seconds: 59)), '9:59:59');
    expect(formatClock(const Duration(hours: 100)), '100:00:00');
  });

  test('formatClock matches formatDuration apart from the leading zero', () {
    for (var s = 0; s < 4000; s += 37) {
      final d = Duration(seconds: s);
      final full = formatDuration(d);
      final clock = formatClock(d);
      expect(full == clock || full == '0$clock', isTrue, reason: '$full vs $clock');
    }
  });
}
