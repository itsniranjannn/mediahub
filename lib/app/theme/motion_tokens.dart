// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';

abstract class MotionTokens {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration feedback = Duration(milliseconds: 160);
  static const Duration page = Duration(milliseconds: 240);
  static const Duration sheet = Duration(milliseconds: 280);

  /// Slow colour drifts in the background (Now Playing tint on track change).
  static const Duration ambient = Duration(milliseconds: 600);

  static const Curve easeOut = Curves.easeOut;
  static const Curve easeIn = Curves.easeIn;

  /// Nav indicator slide and other emphasised moves (240 ms, [page]).
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Volt widgets shrink to this while pressed ([micro], [easeOut]).
  static const double pressedScale = 0.97;

  /// Returns [baseDuration] or [Duration.zero] if reduced motion (disableAnimations) is enabled.
  static Duration duration(BuildContext context, Duration baseDuration) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return Duration.zero;
    }
    return baseDuration;
  }
}
