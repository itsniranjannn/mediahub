// What the Downloads tab says: a failed row explains itself in one plain
// sentence (no downloader jargon, no "update the engine" chore), the link
// card warns before a file that cannot be saved, and iPhone gets its own
// words where Android's would be wrong.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/downloads/ios_playable_formats.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/direct_url_resolver.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/domain/repositories/platform_resolver.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/personal/extractor_errors.dart';

class _FakeResolver extends DirectUrlResolver {
  _FakeResolver(this.answer);
  final SourceInfo Function(Uri uri) answer;
  @override
  Future<SourceInfo> inspect(Uri uri) async => answer(uri);
}

DownloadEntry _failed({required String code, String? detail, String host = 'example.com', String engine = 'http'}) {
  final now = DateTime(2026, 11, 19, 12);
  return DownloadEntry(
    id: '1700000000601',
    url: 'https://$host/v',
    host: host,
    displayName: 'Mountain Song',
    fileName: 'Mountain Song.mp4',
    state: DownloadTaskState.failed.name,
    receivedBytes: 0,
    supportsRange: false,
    createdAt: now,
    updatedAt: now,
    kind: 'video',
    engine: engine,
    errorCode: code,
    errorDetail: detail,
  );
}

void main() {
  tearDown(PlatformInfo.resetForTests);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<DownloadEntry> rows = const [],
    SourceInfo Function(Uri uri)? resolver,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      downloadsStreamProvider.overrideWith((ref) => Stream.value(rows)),
      storageInfoProvider.overrideWith((ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000))),
    ]);
    addTearDown(container.dispose);
    if (resolver != null) container.read(inspectionProvider.notifier).setResolverForTesting(_FakeResolver(resolver));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.build(AppPalette.dark), home: const DownloadsScreen()),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> inspect(WidgetTester tester, String link) async {
    await tester.enterText(find.byType(TextField).first, link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inspect'));
    await tester.pumpAndSettle();
  }

  testWidgets('a YouTube failure from the web link downloader: one plain sentence, no engine chore', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pump(tester, rows: [
      _failed(
        code: 'x_extraction_failed',
        engine: 'extractor',
        host: 'www.youtube.com',
        detail: '[youtube] RpkAZYU8AAA: Requested format is not available. Use --list-formats for a list of available formats',
      ),
    ]);
    // The web link downloader's own words (it already updated itself and
    // tried again by then).
    expect(find.text(ExtractorErrors.downloadMessage('x_extraction_failed')), findsOneWidget);
    final shown = formatPlainErrorMessage('x_extraction_failed');
    expect(shown, isNot(contains('Settings')));
    expect(shown.toLowerCase(), isNot(contains('update')));
    expect(find.textContaining('Requested format'), findsNothing, reason: 'the raw reason stays in the log');
    expect(find.textContaining('Reason:'), findsNothing);
    expect(find.textContaining('downloader engine'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  test('every failure says what happened and what to do, in plain words', () {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    const codes = [
      'insufficient_disk_space', 'write_failed', 'incomplete_download', 'not_media', 'max_size_exceeded',
      'content_range_mismatch', 'size_mismatch', 'connection_error', 'dns_resolution_failed', 'blocked_ip',
      'too_many_redirects', 'http_401', 'http_403', 'http_404', 'http_410', 'http_429', 'http_500', 'http_418',
      'download_error',
    ];
    for (final code in codes) {
      final text = formatPlainErrorMessage(code);
      expect(text, isNot(contains('engine')), reason: code);
      expect(text, isNot(contains('Settings')), reason: code);
      expect(text, isNot(contains('HTTP')), reason: code);
      expect(text.length, lessThan(90), reason: '$code: "$text"');
    }
    expect(formatPlainErrorMessage('http_403'), 'The website refused the download. Check the link, then tap Retry.');
    expect(formatPlainErrorMessage('not_media'), "This link isn't a music or video file. Check the link.");
    expect(formatPlainErrorMessage('insufficient_disk_space'), 'Your phone is out of space. Free up some space, then tap Retry.');
    expect(formatPlainErrorMessage('http_418'), 'The website answered with error 418. Tap Retry.');
    // Web link (yt-dlp) failures: the downloader's own table, word for word.
    for (final code in ['x_extraction_failed', 'x_format_unavailable', 'x_init_failed', 'x_network_error', 'x_new_code']) {
      expect(formatPlainErrorMessage(code), ExtractorErrors.downloadMessage(code), reason: code);
      expect(formatPlainErrorMessage(code), isNot(contains('Settings')), reason: code);
    }
  });

  testWidgets('a file over 2 GB is refused on the card, before anything downloads', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pump(tester, resolver: (uri) => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.download},
          contentType: 'video/mp4',
          contentLength: 3 * 1024 * 1024 * 1024,
          suggestedFilename: 'film.mp4',
        ));
    await inspect(tester, 'https://example.com/film.mp4');
    expect(find.text(tooBigToSaveText), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('a file within the limit keeps its Download button', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pump(tester, resolver: (uri) => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.download},
          contentType: 'video/mp4',
          contentLength: 1024 * 1024 * 1024,
          suggestedFilename: 'film.mp4',
        ));
    await inspect(tester, 'https://example.com/film.mp4');
    expect(find.text(tooBigToSaveText), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('iPhone: a WebM link is warned about up front, with no Download button', (tester) async {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
    await pump(tester, resolver: (uri) => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.download},
          contentType: 'video/webm',
          contentLength: 1024,
          suggestedFilename: 'clip.webm',
        ));
    await inspect(tester, 'https://example.com/clip.webm');
    expect(find.text(IosPlayableFormats.refusal('WebM')), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('Android: the same WebM link downloads as before', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    await pump(tester, resolver: (uri) => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.download},
          contentType: 'video/webm',
          contentLength: 1024,
          suggestedFilename: 'clip.webm',
        ));
    await inspect(tester, 'https://example.com/clip.webm');
    expect(find.textContaining("iPhone can't play"), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('iPhone: the Platform Link card never points to a switch iPhone does not have', (tester) async {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
    await pump(tester);
    await inspect(tester, 'https://www.instagram.com/reel/abc123/');
    expect(find.text('Platform Link'), findsOneWidget);
    expect(find.text(iosPlatformNote('Instagram')), findsOneWidget);
    expect(find.textContaining('Enable web link downloader'), findsNothing);
    expect(find.text('Open link'), findsOneWidget);
  });

  testWidgets('iPhone: a full phone says so plainly', (tester) async {
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
    await pump(tester, rows: [_failed(code: 'insufficient_disk_space')]);
    expect(
      find.text('Your iPhone is full. Free up some space, then tap Retry. Your other files are safe.'),
      findsOneWidget,
    );
  });
}
