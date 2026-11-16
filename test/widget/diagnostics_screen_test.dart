import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mediahub/app/router.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/features/settings/diagnostics_screen.dart';

void main() {
  setUp(() {
    DiagnosticsService.enableDebounce = false;
  });

  testWidgets('DiagnosticsScreen renders null-safely with dataless events', (tester) async {
    final diagnostics = DiagnosticsService.instance;
    await diagnostics.clear();

    // Log events with no payload (e.g. seek, service_start)
    diagnostics.logEvent('service_start');
    diagnostics.logEvent('seek');
    diagnostics.logEvent('play', {'caller': 'in_app'});

    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('service_start'), findsOneWidget);
    expect(find.text('seek'), findsOneWidget);
    expect(find.text('play'), findsOneWidget);
    expect(find.text('caller: in_app'), findsOneWidget);
  });

  testWidgets('DiagnosticsScreen only ever shows redacted links and paths', (tester) async {
    final diagnostics = DiagnosticsService.instance;
    await diagnostics.clear();

    diagnostics.logEvent('player_error', {
      'error': 'Source error for https://rr3---sn.googlevideo.com/videoplayback?ip=203.0.113.9',
      'path': 'could not open /storage/emulated/0/Music/Private Song.mp3',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('player_error'), findsOneWidget);
    // The link inside the error text is replaced; the path runs up to its
    // media file name ("Private Song.mp3"), so the whole path is one <path>.
    expect(find.text('error: Source error for <url>, path: could not open <path>'),
        findsOneWidget);
    expect(find.textContaining('googlevideo'), findsNothing);
    expect(find.textContaining('203.0.113.9'), findsNothing);
    expect(find.textContaining('Private'), findsNothing);
  });

  // The '/video_player' fallback page lives in lib/app/router.dart; it is
  // checked here because what matters most is its single Diagnostics entry.
  group('/video_player without an item shows "Nothing to play"', () {
    Future<GoRouter> pumpRouter(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('HOME'))),
          GoRoute(path: '/video_player', builder: videoPlayerRouteBuilder),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    int noItemEvents() => DiagnosticsService.instance.logs
        .where((line) => line.contains('video_player_no_item'))
        .length;

    testWidgets('opened directly: logged once, and Go back goes Home', (tester) async {
      await DiagnosticsService.instance.clear();
      final router = await pumpRouter(tester);

      router.go('/video_player');
      await tester.pumpAndSettle();
      expect(find.text('Nothing to play'), findsOneWidget);

      // A rebuild (here a new screen size) must not log it again.
      tester.view.physicalSize = const Size(1000, 2000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(find.text('Nothing to play'), findsOneWidget);
      expect(noItemEvents(), 1);
      expect(DiagnosticsService.instance.logs.last, endsWith('video_player_no_item {"extra":"null"}'));

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Nothing to play'), findsNothing);
    });

    testWidgets('pushed with a foreign extra: Go back pops to the page before', (tester) async {
      await DiagnosticsService.instance.clear();
      final router = await pumpRouter(tester);

      router.push('/video_player', extra: 'not a media item');
      await tester.pumpAndSettle();
      expect(find.text('Nothing to play'), findsOneWidget);
      expect(noItemEvents(), 1);
      expect(DiagnosticsService.instance.logs.last, endsWith('{"extra":"String"}'),
          reason: 'only the type is logged, never the value');

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Nothing to play'), findsNothing);
    });
  });
}
