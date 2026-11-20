import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_theme.dart';

/// The theme of the Ink Dock and the stage (Now Playing, video player): dark
/// in both app themes. `MediaHubApp` installs [AppTheme.darkTheme], or
/// [AppTheme.classicTheme] while Bijuli Classic is chosen, above the router.
class InkTheme extends InheritedWidget {
  const InkTheme({super.key, required this.data, required super.child});

  /// The dark theme the dock and the stage wrap themselves in.
  final ThemeData data;

  /// The nearest [InkTheme]'s data, or [AppTheme.darkTheme] when there is
  /// none (a widget test that pumps a dock or player on its own).
  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InkTheme>()?.data ?? AppTheme.darkTheme;

  /// The palette of [of]: [AppPalette.dark] or [AppPalette.classic].
  static AppPalette paletteOf(BuildContext context) =>
      of(context).extension<AppPalette>() ?? AppPalette.dark;

  @override
  bool updateShouldNotify(InkTheme oldWidget) => !identical(data, oldWidget.data);
}
