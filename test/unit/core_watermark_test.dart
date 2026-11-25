// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/core_watermark.dart';

void main() {
  test('authorship mark decodes and verifies', () {
    expect(CoreWatermark.author, 'Niranjan');
    expect(CoreWatermark.fullName, 'Niranjan Katwal');
    expect(CoreWatermark.verifyIntegrity(), isTrue);
  });
}
