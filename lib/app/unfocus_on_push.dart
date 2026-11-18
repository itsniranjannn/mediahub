import 'package:flutter/widgets.dart';

/// Lets go of a text field's focus when a page, sheet or dialog opens.
///
/// A page remembers which field had focus; when the page on top of it closes,
/// Flutter gives that field focus again and the keyboard pops up on its own.
/// Found on the emulator: search the library, open an album, come back, and
/// the keyboard was up again. Spotify and YouTube Music leave it closed.
///
/// Give it to `GoRouter(observers: ...)`: go_router also forwards the root
/// observers to every tab's navigator (StatefulShellRoute's
/// `notifyRootObserver`, on by default), so pushes inside a tab are covered.
class UnfocusOnPush extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The pushed route has not built yet, so the field still has focus here.
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null) return;
    final isTextField = context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isTextField) focus.unfocus();
  }
}
