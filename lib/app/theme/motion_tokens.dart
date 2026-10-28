import 'package:flutter/material.dart';

abstract class MotionTokens {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration feedback = Duration(milliseconds: 160);
  static const Duration page = Duration(milliseconds: 240);
  static const Duration sheet = Duration(milliseconds: 280);

  static const Curve easeOut = Curves.easeOut;
  static const Curve easeIn = Curves.easeIn;

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
