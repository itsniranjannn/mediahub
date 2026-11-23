// The drag handle on every sheet is read as "Dismiss"; activating it (a
// screen reader's double tap) closes the sheet, also for sheets opened over
// the Ink Dock on the root navigator from inside a tab's own navigator.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';

Future<void> _pumpOpener(WidgetTester tester, WidgetBuilder sheet) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      // A tab's own navigator, as in the app shell.
      body: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: sheet,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Activates the "Dismiss" handle the way TalkBack does.
Future<void> _activateDismiss(WidgetTester tester) async {
  final handle = find.semantics.byLabel('Dismiss');
  expect(handle, findsOne, reason: 'one Dismiss handle');
  tester.semantics.tap(handle);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a plain sheet closes from its Dismiss handle', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOpener(tester, (_) => const SizedBox(height: 200, child: Text('Sheet')));
    expect(find.byType(BottomSheet), findsOneWidget);
    await _activateDismiss(tester);
    expect(find.byType(BottomSheet), findsNothing);
    handle.dispose();
  });

  testWidgets('Choose quality closes from its Dismiss handle', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOpener(
      tester,
      (_) => FormatSelectionSheet(
        metadata: const ExtractorMetadata(id: 'x', title: 'T', uploader: 'U', durationSec: 60, thumbnailUrl: '', formats: []),
        onSelect: (_) {},
      ),
    );
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    await _activateDismiss(tester);
    expect(find.byType(FormatSelectionSheet), findsNothing);
    handle.dispose();
  });
}
