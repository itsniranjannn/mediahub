import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/utils/formatters.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';

const _androidHelper = 'Paste a YouTube, Instagram or direct https link';
// Without yt-dlp YouTube still works (the files YouTube serves directly), so
// the helper says so (it used to read "Enter a direct https link to audio or video").
const _directOnlyHelper = 'Paste a YouTube link, or a direct https link to audio or video';
const _youtubeHelper = 'YouTube link: supported. Tap Choose quality to save the video or just its audio';

/// "Enable web link downloader" fixed on or off, without the settings file or
/// the extractor start-up the real notifier runs.
class _FixedPersonalTools extends PersonalToolsNotifier {
  _FixedPersonalTools(this._enabled);

  final bool _enabled;

  @override
  PersonalToolsState build() => PersonalToolsState(isEnabled: _enabled);

  void set(bool enabled) => state = PersonalToolsState(isEnabled: enabled);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  tearDown(() async {
    PlatformInfo.resetForTests();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester, {bool? downloaderSetting}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
          storageInfoProvider.overrideWith(
            (ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000)),
          ),
          if (downloaderSetting != null)
            personalToolsProvider.overrideWith(() => _FixedPersonalTools(downloaderSetting)),
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  InputDecoration linkDecoration(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).decoration!;

  testWidgets('Android (bundled yt-dlp): helper mentions YouTube and Instagram links', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pumpScreen(tester);

    expect(find.text(_androidHelper), findsOneWidget);
    expect(find.text(_directOnlyHelper), findsNothing);
    expect(linkDecoration(tester).hintText, 'https://...');

    // An invalid link still swaps the helper for the error.
    await tester.enterText(find.byType(TextField).first, 'http://example.com/clip.mp4');
    await tester.pumpAndSettle();
    expect(find.text('Only secure HTTPS links are allowed.'), findsOneWidget);
    expect(find.text(_androidHelper), findsNothing);

    // A YouTube link in the field: the helper and the button say it is supported.
    await tester.enterText(find.byType(TextField).first, 'https://youtu.be/bIQkviE_JJo');
    await tester.pumpAndSettle();
    expect(find.text(_youtubeHelper), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Choose quality'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com/clip.mp4');
    await tester.pumpAndSettle();
    expect(find.text(_androidHelper), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Inspect'), findsOneWidget);
  });

  testWidgets('Android with "Enable web link downloader" off: helper asks for a direct link', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pumpScreen(tester, downloaderSetting: false);

    expect(find.text(_directOnlyHelper), findsOneWidget);
    expect(find.text(_androidHelper), findsNothing);
    expect(linkDecoration(tester).hintText, 'https://...');
  });

  testWidgets('Android: the helper follows the setting when it is switched on', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pumpScreen(tester, downloaderSetting: false);
    expect(find.text(_directOnlyHelper), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(DownloadsScreen)));
    (container.read(personalToolsProvider.notifier) as _FixedPersonalTools).set(true);
    await tester.pump();
    expect(find.text(_androidHelper), findsOneWidget);
    expect(find.text(_directOnlyHelper), findsNothing);
  });

  testWidgets('iOS (no extractor): helper asks for a YouTube or direct link', (tester) async {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
    await pumpScreen(tester);

    expect(find.text(_directOnlyHelper), findsOneWidget);
    expect(find.text(_androidHelper), findsNothing);
    expect(linkDecoration(tester).hintText, 'https://...');

    // Every YouTube link shape is recognised, including the canonical one
    // the Online tab copies.
    for (final link in [
      'https://youtu.be/bIQkviE_JJo',
      'https://youtube.com/shorts/bIQkviE_JJo',
      'https://music.youtube.com/watch?v=bIQkviE_JJo',
      'https://m.youtube.com/watch?v=bIQkviE_JJo&pp=x',
    ]) {
      await tester.enterText(find.byType(TextField).first, link);
      await tester.pumpAndSettle();
      expect(find.text(_youtubeHelper), findsOneWidget, reason: link);
      expect(find.widgetWithText(FilledButton, 'Choose quality'), findsOneWidget, reason: link);
    }

    // A playlist is not one video: plain Inspect.
    await tester.enterText(find.byType(TextField).first, 'https://www.youtube.com/playlist?list=PL123');
    await tester.pumpAndSettle();
    expect(find.text(_directOnlyHelper), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Inspect'), findsOneWidget);
  });

  testWidgets('file-style download titles wrap between words; semantics keep the real name', (tester) async {
    const title = 'Audit_Long_Tone_5min';
    const fileName = 'Audit_Long_Tone_5min.mp4';
    final now = DateTime(2026, 1, 1);
    // drift completes on the real event loop: only through runAsync here.
    await tester.runAsync(() async {
      await db.into(db.downloadsTable).insert(
            DownloadsTableCompanion.insert(
              id: 'dl_video_1',
              url: 'https://example.com/$fileName',
              host: 'example.com',
              displayName: title,
              fileName: fileName,
              state: DownloadTaskState.completed.name,
              receivedBytes: const d.Value(2048),
              totalBytes: const d.Value(2048),
              kind: const d.Value('video'),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          storageInfoProvider.overrideWith(
            (ref) => Future.value(const StorageInfo(usedBytes: 2048, freeBytes: 1000000000)),
          ),
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 60));
    }

    final titleText = tester.widget<Text>(find.text(breakableTitle(title)));
    expect(titleText.data, isNot(title)); // has wrap points after each '_'
    expect(titleText.semanticsLabel, title);
    expect(find.text(title), findsNothing);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final dialogText = tester.widget<Text>(
      find.text('Delete "${breakableTitle(fileName)}"? Your other files are safe.'),
    );
    expect(dialogText.semanticsLabel, 'Delete "$fileName"? Your other files are safe.');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Unmount so the drift stream is cancelled, then let drift's own clean-up
    // timer fire (an un-fired timer fails the test).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
