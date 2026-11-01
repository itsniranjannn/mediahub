import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/direct_url_resolver.dart';
import 'package:mediahub/domain/repositories/platform_resolver.dart';
import 'package:drift/native.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

class _FakeDirectUrlResolver extends DirectUrlResolver {
  final Future<SourceInfo> Function(Uri uri) onInspect;
  _FakeDirectUrlResolver(this.onInspect);

  @override
  Future<SourceInfo> inspect(Uri uri) => onInspect(uri);
}

void main() {
  group('TASK 5.2c Item 1, 2, 3: Downloads Screen URL Logic & Known Platforms', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('Item 1: Pasting YouTube link validates and enables Inspect button', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': 'https://youtu.be/bIQkviE_JJo?si=0Jabc'};
          }
          return null;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
            storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
          ],
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Paste from clipboard
      await tester.tap(find.byTooltip('Paste from clipboard'));
      await tester.pumpAndSettle();

      // Verify Inspect button is enabled
      final inspectBtn = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Inspect'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(inspectBtn.onPressed, isNotNull);
      expect(find.text('Enter a direct https link to audio or video'), findsOneWidget);
    });

    testWidgets('Item 2: Helper text when valid, error when invalid, Done key inspects, cancel works', (tester) async {
      final fakeCompleter = Completer<SourceInfo>();
      final fakeResolver = _FakeDirectUrlResolver((uri) => fakeCompleter.future);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
          storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
        ],
      );
      container.read(inspectionProvider.notifier).setResolverForTesting(fakeResolver);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).first;

      // Type invalid scheme
      await tester.enterText(textField, 'http://example.com/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Only secure HTTPS links are allowed.'), findsOneWidget);
      expect(find.text('Enter a direct https link to audio or video'), findsNothing);

      // Type valid URL
      await tester.enterText(textField, 'https://example.com/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Enter a direct https link to audio or video'), findsOneWidget);

      // Trigger Done on keyboard
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(); // Start inspecting

      // Cancel button and progress indicator are shown
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Inspection was cancelled.'), findsOneWidget);
      expect(find.text('Inspect'), findsOneWidget);

      fakeCompleter.complete(SourceInfo(
        providerId: 'direct',
        uri: Uri.parse('https://example.com/audio.mp3'),
        capabilities: {},
      ));
    });

    testWidgets('Item 3: Known platforms show friendly message with Open link and no Download button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
            storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
          ],
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).first;

      // 1. YouTube
      await tester.enterText(textField, 'https://youtu.be/bIQkviE_JJo?si=0Jabc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect'));
      await tester.pumpAndSettle();

      expect(find.text('Platform Link'), findsOneWidget);
      expect(
        find.text('YouTube pages are not direct media files. MediaHub cannot download from this service. Open it in the YouTube app or use its own offline feature.'),
        findsOneWidget,
      );
      expect(find.text('Open link'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      // 2. Spotify
      await tester.enterText(textField, 'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect'));
      await tester.pumpAndSettle();

      expect(
        find.text('Spotify pages are not direct media files. MediaHub cannot download from this service. Open it in the Spotify app or use its own offline feature.'),
        findsOneWidget,
      );
      expect(find.text('Open link'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      // 3. Lookalike domain does NOT match platform
      // Re-inspect with lookalike
      await tester.enterText(textField, 'https://notyoutube.com.evil.example/audio.mp3');
      await tester.pumpAndSettle();
      expect(find.text('Enter a direct https link to audio or video'), findsOneWidget);
    });
  });
}
