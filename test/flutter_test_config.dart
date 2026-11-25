// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:mediahub/shared/widgets/planet_backdrop.dart';

/// The Settings planet turns on a periodic timer, which would keep
/// `pumpAndSettle` from settling; tests that check its motion turn it back on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PlanetBackdrop.debugAnimate = false;
  await testMain();
}
