import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One [TextScaler] for a row of one-line labels in the same [style] (the
/// five nav labels, Home's quick tiles): the user's text size, shrunk just
/// enough that the widest of [labels] fits [maxWidth]. Every label in the row
/// then ends up the same size, instead of only the long one shrinking (which
/// read as broken). Returns the user's own size when everything fits.
///
/// Give each label's Text this scaler (and keep a `FittedBox(scaleDown)`
/// around it as a guard against sub-pixel rounding).
TextScaler sharedLabelScaler(
  BuildContext context, {
  required Iterable<String> labels,
  required TextStyle style,
  required double maxWidth,
}) {
  final user = MediaQuery.textScalerOf(context);
  final fontSize = style.fontSize ?? 14;
  final userFactor = user.scale(fontSize) / fontSize;
  if (maxWidth <= 0) return user;
  final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;

  double widest(double factor) {
    var width = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: TextScaler.linear(factor),
        maxLines: 1,
      )..layout();
      width = math.max(width, painter.width);
      painter.dispose();
    }
    return width;
  }

  var factor = userFactor;
  // Letter spacing does not scale with the font, so a second pass closes
  // the small gap the first one leaves.
  for (var pass = 0; pass < 3; pass++) {
    final width = widest(factor);
    if (width <= maxWidth) break;
    factor *= maxWidth / width;
  }
  return factor == userFactor ? user : TextScaler.linear(factor);
}
