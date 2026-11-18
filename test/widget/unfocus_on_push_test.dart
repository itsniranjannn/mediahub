import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/unfocus_on_push.dart';

/// Found on the emulator: search the library, open an album, press back,
/// and the keyboard came up again by itself.
void main() {
  Future<FocusNode> pumpSearch(WidgetTester tester, {required bool observe}) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [if (observe) UnfocusOnPush()],
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextField(focusNode: field),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Album page'))),
                  ),
                  child: const Text('open album'),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(content: TextField(autofocus: true, key: Key('rename'))),
                  ),
                  child: const Text('rename'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'raga');
    expect(field.hasFocus, isTrue);
    return field;
  }

  Future<void> openAndCloseAlbum(WidgetTester tester) async {
    await tester.tap(find.text('open album'));
    await tester.pumpAndSettle();
    expect(find.text('Album page'), findsOne);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
  }

  testWidgets('without it, closing a page gives the search field focus back (the bug)', (tester) async {
    final field = await pumpSearch(tester, observe: false);
    await openAndCloseAlbum(tester);
    expect(field.hasFocus, isTrue);
  });

  testWidgets('with it, the search field stays unfocused after the page closes', (tester) async {
    final field = await pumpSearch(tester, observe: true);
    await openAndCloseAlbum(tester);
    expect(field.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    // The text the user typed is still there.
    expect(find.text('raga'), findsOne);
  });

  // The app gives the observer to GoRouter only; a push inside a tab happens
  // on that tab's own navigator, which go_router feeds the root observers.
  testWidgets('given to GoRouter only, it also covers a page pushed inside a tab', (tester) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    final router = GoRouter(
      initialLocation: '/music',
      observers: [UnfocusOnPush()],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/music',
                  builder: (context, state) => Column(
                    children: [
                      TextField(focusNode: field),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Album page'))),
                        ),
                        child: const Text('open album'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.showKeyboard(find.byType(TextField));
    expect(field.hasFocus, isTrue);

    await tester.tap(find.text('open album'));
    await tester.pumpAndSettle();
    expect(find.text('Album page'), findsOne);
    // The album page sits on the tab's navigator, not the root one.
    Navigator.of(tester.element(find.text('Album page'))).pop();
    await tester.pumpAndSettle();

    expect(field.hasFocus, isFalse);
  });

  testWidgets('a dialog with its own autofocus field still gets focus', (tester) async {
    await pumpSearch(tester, observe: true);
    await tester.tap(find.text('rename'));
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<TextField>()?.key, const Key('rename'));
  });
}
