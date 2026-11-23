import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/downloads/youtube_stream_source.dart';
import 'package:mediahub/data/repositories/direct_url_resolver.dart';
import 'package:mediahub/domain/models/download_progress.dart';
import 'package:mediahub/domain/repositories/platform_resolver.dart';
import 'package:mediahub/features/downloads/download_link_inbox.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/downloads/fast_youtube_extractor_resolver.dart';
import 'package:mediahub/features/downloads/youtube_direct_flow.dart';
import 'package:mediahub/features/downloads/youtube_direct_resolver.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';

import '../unit/fake_extractor_backend.dart';
import '../unit/fake_online_source.dart';

const _idA = 'dQw4w9WgXcQ';
const _idB = 'aqz-KE-bpKQ';
const _linkA = 'https://youtu.be/$_idA';
const _linkB = 'https://youtu.be/$_idB';
const _dialogText = 'Finding available qualities...';
const _audioLabel = 'Audio only (M4A, 128 kbps)';
/// iOS wording for the same stream (no MP3 there, so AAC is named).
const _iosAudioLabel = 'M4A (AAC) · 128 kbps';

/// Records what would be downloaded; nothing touches the network or disk.
class _RecordingEngine extends Fake implements DownloadEngine {
  final List<Map<String, Object?>> enqueued = [];

  @override
  Stream<DownloadProgressUpdate> get progressStream => const Stream.empty();

  @override
  Future<void> enqueueDownload({
    required String id,
    required Uri url,
    required String displayName,
    required String suggestedFileName,
    String? kind,
    String? thumbnailUrl,
    String? qualityLabel,
    String? uploader,
    int? durationSec,
    int? totalBytes,
    String? linkSource,
  }) async {
    enqueued.add({
      'url': url,
      'displayName': displayName,
      'suggestedFileName': suggestedFileName,
      'kind': kind,
      'thumbnailUrl': thumbnailUrl,
      'qualityLabel': qualityLabel,
      'uploader': uploader,
      'durationSec': durationSec,
      'totalBytes': totalBytes,
      'linkSource': linkSource,
    });
  }
}

class _FakeQueueCoordinator extends DownloadQueueCoordinatorNotifier {
  int triggers = 0;

  @override
  void build() {}

  @override
  Future<void> trigger() async => triggers++;
}

class _FixedPersonalTools extends PersonalToolsNotifier {
  _FixedPersonalTools(this._enabled);

  final bool _enabled;

  @override
  PersonalToolsState build() => PersonalToolsState(isEnabled: _enabled);
}

class _FakeDirectUrlResolver extends DirectUrlResolver {
  _FakeDirectUrlResolver(this.onInspect);

  final Future<SourceInfo> Function(Uri uri) onInspect;
  final List<Uri> calls = [];

  @override
  Future<SourceInfo> inspect(Uri uri) {
    calls.add(uri);
    return onInspect(uri);
  }
}

/// yt-dlp stand-in whose answer each test scripts.
class _ScriptedBackend extends FakeExtractorBackend {
  Future<ExtractorMetadata> Function(String url)? onGetInfo;
  final List<String> infoCalls = [];

  @override
  Future<ExtractorMetadata> getInfo(String url, {String? requestId}) {
    infoCalls.add(url);
    final handler = onGetInfo;
    return handler != null ? handler(url) : super.getInfo(url);
  }
}

YoutubeVideoDetails _detailsFor(String id) => YoutubeVideoDetails(
      id: id,
      title: id == _idA ? 'Mountain Song' : 'River Song',
      author: 'Himal Sessions',
      duration: const Duration(minutes: 3, seconds: 30),
      thumbnailUrl: 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
    );

void main() {
  late AppDatabase db;
  late FakeOnlineSource source;
  late _RecordingEngine engine;
  late _FakeQueueCoordinator coordinator;
  late _FakeDirectUrlResolver directResolver;
  late _ScriptedBackend backend;
  late Future<YoutubeVideoDetails> Function(String id) details;
  late int? freeBytes;

  setUp(() {
    // Lookups are logged; no 3 s write timer may outlive a widget test.
    DiagnosticsService.enableDebounce = false;
    db = AppDatabase(NativeDatabase.memory());
    source = FakeOnlineSource();
    engine = _RecordingEngine();
    coordinator = _FakeQueueCoordinator();
    backend = _ScriptedBackend();
    details = (id) async => _detailsFor(id);
    freeBytes = 50 * 1024 * 1024 * 1024;
    directResolver = _FakeDirectUrlResolver((uri) async => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: {SourceCapability.download},
          contentType: 'audio/mpeg',
          contentLength: 5 * 1024 * 1024,
          suggestedFilename: 'song.mp3',
          supportsRange: true,
        ));
    // iPhone unless a test says otherwise: no yt-dlp.
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = true;
    FastYoutubeExtractorResolver.overrideResolver = (uri) async => null;
  });

  tearDown(() async {
    FastYoutubeExtractorResolver.overrideResolver = null;
    PlatformInfo.resetForTests();
    await db.close();
  });

  ProviderContainer makeContainer({bool? personalTools}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        downloadsStreamProvider.overrideWith((ref) => Stream.value([])),
        storageInfoProvider.overrideWith(
          (ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000)),
        ),
        downloadEngineProvider.overrideWithValue(engine),
        downloadQueueCoordinatorProvider.overrideWith(() => coordinator),
        downloadNoticeAgreedProvider.overrideWithBuild((ref, notifier) => true),
        downloadFreeSpaceProvider.overrideWithValue(() async => freeBytes),
        extractorBackendProvider.overrideWithValue(backend),
        youtubeDirectResolverProvider.overrideWith(
          (ref) => YoutubeDirectResolver(
            source: source,
            fetchDetails: (id) => details(id),
            mp4Only: PlatformInfo.isIOS,
            detailsTimeout: const Duration(seconds: 1),
          ),
        ),
        if (personalTools != null) personalToolsProvider.overrideWith(() => _FixedPersonalTools(personalTools)),
      ],
    );
    container.read(inspectionProvider.notifier).setResolverForTesting(directResolver);
    addTearDown(container.dispose);
    return container;
  }

  /// A phone-sized screen tall enough for the whole quality sheet.
  void usePhone(WidgetTester tester) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(412 * 2, 1400 * 2);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpScreen(WidgetTester tester, ProviderContainer container, {ValueListenable<bool>? visible}) async {
    usePhone(tester);
    const screen = DownloadsScreen();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: visible == null
              ? screen
              : ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (context, on, child) => TickerMode(enabled: on, child: child!),
                  child: screen,
                ),
        ),
      ),
    );
  }

  /// Lets dialogs, sheets and snack bars animate (the lookup dialog's spinner
  /// never settles, so no pumpAndSettle while it may be up).
  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  String fieldText(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  void send(ProviderContainer c, String url, {String? title, bool inspect = true}) =>
      c.read(downloadLinkInboxProvider.notifier).send(PendingDownloadLink(url, title: title, inspect: inspect));

  testWidgets('iOS: a link sent before Downloads opens goes straight to the quality sheet and is queued',
      (tester) async {
    final container = makeContainer();
    send(container, _linkA, title: 'Mountain Song');
    await pumpScreen(tester, container);
    await animate(tester);

    expect(container.read(downloadLinkInboxProvider), isNull, reason: 'taken exactly once');
    expect(fieldText(tester), _linkA);
    expect(find.text('Link from Online: Mountain Song'), findsOneWidget);
    expect(source.streamCalls, [_idA]);
    expect(find.text(_dialogText), findsNothing);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    expect(find.text('360p'), findsOneWidget);
    expect(find.text('MP4 · 12.0 MB'), findsOneWidget, reason: 'sizes are shown when known');
    // Audio choices sit in the sheet's Audio section.
    await tester.tap(find.text('Audio'));
    await tester.pump();
    expect(find.text(_iosAudioLabel), findsOneWidget);
    expect(find.text(YoutubeDirectDownloadFlow.sheetNote), findsOneWidget);
    expect(find.text('Platform Link'), findsOneWidget, reason: 'the card stays behind the sheet');

    await tester.tap(find.text(_iosAudioLabel));
    await animate(tester);

    expect(find.byType(FormatSelectionSheet), findsNothing);
    final queued = engine.enqueued.single;
    final url = queued['url']! as Uri;
    expect(url.host, 'rr1---sn-test.googlevideo.com');
    expect(url.scheme, 'https');
    expect(queued['kind'], 'audio');
    expect(queued['displayName'], 'Mountain Song');
    expect(queued['suggestedFileName'], 'Mountain Song.m4a');
    expect(queued['uploader'], 'Himal Sessions');
    expect(queued['qualityLabel'], 'Audio 128 kbps');
    expect(queued['durationSec'], 210);
    expect(queued['totalBytes'], 3 * 1024 * 1024);
    expect(queued['thumbnailUrl'], 'https://i.ytimg.com/vi/$_idA/mqdefault.jpg');
    // YouTube's link to the file expires after some hours: the row keeps the
    // video and the choice, so a resume or retry later can find it again.
    final kept = YoutubeStreamSource.tryDecode(queued['linkSource'] as String?);
    expect(kept, isNotNull);
    expect(kept!.videoId, _idA);
    expect(kept.choiceId, 'yt_audio');
    expect(kept.itag, 140);
    expect(DateTime.now().difference(kept.resolvedAt).inMinutes, lessThan(5));
    expect(coordinator.triggers, 1);
    expect(find.text('Added to Downloads: Mountain Song (Audio 128 kbps)'), findsOneWidget);
    expect(fieldText(tester), isEmpty, reason: 'the queued link is cleared');
    expect(find.text('Platform Link'), findsNothing);
  });

  testWidgets('a link sent while Downloads is open is picked up too (direct file: Inspect)', (tester) async {
    final container = makeContainer();
    await pumpScreen(tester, container);
    await tester.pumpAndSettle();

    send(container, 'https://example.com/song.mp3');
    await tester.pumpAndSettle();

    expect(container.read(downloadLinkInboxProvider), isNull);
    expect(fieldText(tester), 'https://example.com/song.mp3');
    expect(find.text('Link from Online'), findsOneWidget);
    expect(directResolver.calls, [Uri.parse('https://example.com/song.mp3')]);
    expect(find.text('Inspection Result'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    // A second link replaces the first one.
    send(container, _linkB, title: 'River Song');
    await animate(tester);
    expect(fieldText(tester), _linkB);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    expect(source.streamCalls, [_idB]);
  });

  testWidgets('inspect: false only fills the field, which says the YouTube link is supported', (tester) async {
    final container = makeContainer();
    send(container, _linkA, inspect: false);
    await pumpScreen(tester, container);
    await tester.pumpAndSettle();

    expect(fieldText(tester), _linkA);
    expect(source.streamCalls, isEmpty);
    expect(find.byType(FormatSelectionSheet), findsNothing);
    expect(find.text('YouTube link: supported. Tap Choose quality to save the video or just its audio'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Choose quality'), findsOneWidget);
    expect(find.text('Inspect'), findsNothing);

    // Editing the field away from the handed link removes the note.
    await tester.enterText(find.byType(TextField).first, 'https://example.com/a.mp3');
    await tester.pumpAndSettle();
    expect(find.text('Link from Online'), findsNothing);
    expect(find.text('Inspect'), findsOneWidget);
  });

  testWidgets('a link sent while a quality lookup runs waits in the field; nothing is lost or started',
      (tester) async {
    final container = makeContainer();
    final slow = Completer<OnlineStreams>();
    source.onStreams = (id) => id == _idA ? slow.future : Future.value(FakeOnlineSource.sampleStreams);
    send(container, _linkA, title: 'Mountain Song');
    await pumpScreen(tester, container);
    await animate(tester);
    expect(find.text(_dialogText), findsOneWidget);

    send(container, _linkB, title: 'River Song');
    await animate(tester);

    expect(container.read(downloadLinkInboxProvider), isNull);
    expect(fieldText(tester), _linkB, reason: 'the new link is kept in the field');
    expect(source.streamCalls, [_idA], reason: 'no second lookup on top of the running one');
    expect(
      find.text('Link from Online is ready: River Song. When the current download choice is done, tap Choose quality.'),
      findsOneWidget,
    );

    // The first lookup ends: its sheet opens and its pick is queued.
    slow.complete(FakeOnlineSource.sampleStreams);
    await animate(tester);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    expect(find.text('Mountain Song'), findsWidgets);
    await tester.tap(find.text('360p'));
    await animate(tester);

    expect(engine.enqueued.single['displayName'], 'Mountain Song');
    expect(engine.enqueued.single['suggestedFileName'], 'Mountain Song.mp4');
    expect(fieldText(tester), _linkB, reason: 'queueing the first link never clears the second');

    // The waiting link starts when the user taps Choose quality.
    await tester.tap(find.widgetWithText(FilledButton, 'Choose quality'));
    await animate(tester);
    expect(source.streamCalls, [_idA, _idB]);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    expect(find.text('River Song'), findsWidgets);
  });

  testWidgets('a link sent while a direct-link check runs waits in the field', (tester) async {
    final checking = Completer<SourceInfo>();
    directResolver = _FakeDirectUrlResolver((uri) => checking.future);
    final container = makeContainer();
    await pumpScreen(tester, container);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://example.com/slow.mp3');
    await tester.pump();
    await tester.tap(find.text('Inspect'));
    await tester.pump();
    expect(find.text('Checking link...'), findsOneWidget);

    send(container, _linkA, title: 'Mountain Song');
    await tester.pump();
    await tester.pump();

    expect(fieldText(tester), _linkA);
    expect(find.text('Checking link...'), findsOneWidget, reason: 'the running check is not disturbed');
    expect(source.streamCalls, isEmpty);
    expect(find.textContaining('Link from Online is ready: Mountain Song.'), findsOneWidget);

    checking.complete(SourceInfo(providerId: 'direct', uri: Uri.parse('https://example.com/slow.mp3'), capabilities: {}));
    await tester.pumpAndSettle();
  });

  testWidgets('a link sent while Downloads is in the background waits until the tab is shown', (tester) async {
    final container = makeContainer();
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);
    await pumpScreen(tester, container, visible: visible);
    await tester.pumpAndSettle();

    send(container, 'https://example.com/song.mp3');
    await tester.pumpAndSettle();
    expect(container.read(downloadLinkInboxProvider), isNotNull, reason: 'still waiting in the inbox');
    expect(fieldText(tester), isEmpty);
    expect(directResolver.calls, isEmpty);

    visible.value = true;
    await tester.pumpAndSettle();
    expect(container.read(downloadLinkInboxProvider), isNull);
    expect(fieldText(tester), 'https://example.com/song.mp3');
    expect(directResolver.calls, hasLength(1));
  });

  testWidgets('a live video is refused in plain words', (tester) async {
    details = (id) async => YoutubeVideoDetails(id: id, title: 'On air', author: 'X', isLive: true);
    final container = makeContainer();
    send(container, 'https://www.youtube.com/live/$_idA');
    await pumpScreen(tester, container);
    await animate(tester);

    expect(find.byType(FormatSelectionSheet), findsNothing);
    expect(find.text("Live streams can't be downloaded. Try again after the stream has ended."), findsOneWidget);
    expect(engine.enqueued, isEmpty);
    expect(fieldText(tester), 'https://www.youtube.com/live/$_idA', reason: 'the link stays for another try');
  });

  testWidgets('not enough free space: refused before anything is queued', (tester) async {
    freeBytes = 50 * 1024 * 1024; // 50 MB: less than 12 MB + the 100 MB margin
    final container = makeContainer();
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);

    await tester.tap(find.text('360p'));
    await animate(tester);
    expect(engine.enqueued, isEmpty);
    expect(find.text('Not enough free space: this download needs about 12.0 MB and 50.0 MB is free.'), findsOneWidget);
  });

  testWidgets('iPhone: free space it cannot know never refuses a download up front', (tester) async {
    // Nothing on iPhone tells the free space (it used to be a made-up 10 GB).
    freeBytes = null;
    final container = makeContainer();
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);

    await tester.tap(find.text('360p'));
    await animate(tester);
    expect(engine.enqueued, hasLength(1));
    expect(find.textContaining('Not enough free space'), findsNothing);
  });

  testWidgets('Android with the web link downloader off: YouTube uses the direct path, Settings offers more',
      (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    final container = makeContainer(personalTools: false);
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);

    expect(backend.infoCalls, isEmpty, reason: 'yt-dlp is off');
    expect(source.streamCalls, [_idA]);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    expect(find.text(YoutubeDirectDownloadFlow.sheetNote), findsOneWidget);
    expect(YoutubeDirectDownloadFlow.sheetNote, contains('Enable web link downloader'));

    // Close the sheet: the card offers both ways.
    await tester.tapAt(const Offset(200, 40));
    await animate(tester);
    expect(find.widgetWithText(FilledButton, 'Choose quality'), findsWidgets);
    expect(find.text('Enable downloader'), findsOneWidget);
    expect(find.textContaining('For every quality up to 4K'), findsOneWidget);
  });

  testWidgets('Android without yt-dlp: a YouTube download is queued as before (no link source)', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    // Android asks for the notification permission first: granted.
    const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (call) async => 1);
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    final container = makeContainer(personalTools: false);
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);

    await tester.tap(find.text('360p'));
    await animate(tester);
    final queued = engine.enqueued.single;
    expect((queued['url']! as Uri).host, 'rr1---sn-test.googlevideo.com');
    expect(queued['linkSource'], isNull);
  });

  testWidgets('Android with yt-dlp on: YouTube goes to yt-dlp (every quality)', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    final container = makeContainer(personalTools: true);
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);

    expect(backend.infoCalls, [_linkA]);
    expect(source.streamCalls, isEmpty);
    expect(find.text('Best available (1080p)'), findsOneWidget, reason: 'the yt-dlp quality list');
  });

  testWidgets('Android with yt-dlp on: a web page from another site offers no Choose quality', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    // A news page: yt-dlp does not read this site, so Choose quality could
    // only end in "not supported".
    directResolver = _FakeDirectUrlResolver((uri) async => SourceInfo(
          providerId: 'direct',
          uri: uri,
          capabilities: const {},
          contentType: 'text/html; charset=utf-8',
        ));
    final container = makeContainer(personalTools: true);
    send(container, 'https://news.example.com/story/123');
    await pumpScreen(tester, container);
    await animate(tester);

    expect(find.text('Inspection Result'), findsOneWidget);
    expect(find.textContaining('This is a web page'), findsOneWidget);
    expect(find.text('Open link'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Choose quality'), findsNothing);
    expect(backend.infoCalls, isEmpty);
  });

  testWidgets('Android: when yt-dlp cannot run, a YouTube link falls back to the direct path', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    backend.onGetInfo = (_) async => throw const ExtractorException('INIT_FAILED', 'no python');
    final container = makeContainer(personalTools: true);
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);
    await animate(tester);

    expect(backend.infoCalls, [_linkA]);
    expect(source.streamCalls, [_idA]);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
    // Audio choices sit in the sheet's Audio section.
    await tester.tap(find.text('Audio'));
    await tester.pump();
    expect(find.text(_audioLabel), findsOneWidget);
    // The downloader is already on: the sheet says why the list is short,
    // instead of asking to turn it on.
    expect(find.text(YoutubeDirectDownloadFlow.fallbackSheetNote), findsOneWidget);
    expect(find.text(YoutubeDirectDownloadFlow.sheetNote), findsNothing);
  });

  testWidgets('Android: a link problem from yt-dlp is shown, not hidden by the fallback', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    backend.onGetInfo = (_) async => throw const ExtractorException('PRIVATE_CONTENT', 'private');
    final container = makeContainer(personalTools: true);
    send(container, _linkA);
    await pumpScreen(tester, container);
    await animate(tester);

    expect(source.streamCalls, isEmpty);
    expect(find.text('This video is private and cannot be downloaded.'), findsOneWidget);
  });

  testWidgets('the paste button is the only way the clipboard is read', (tester) async {
    var clipboardReads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardReads++;
        return <String, dynamic>{'text': '  https://youtu.be/$_idA  '};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final container = makeContainer();
    await pumpScreen(tester, container);
    await tester.pumpAndSettle();
    expect(clipboardReads, 0, reason: 'no automatic clipboard reading');
    expect(find.text('Paste a YouTube link, or a direct https link to audio or video'), findsOneWidget);

    await tester.tap(find.byTooltip('Paste from clipboard'));
    await tester.pumpAndSettle();
    expect(clipboardReads, 1);
    expect(fieldText(tester), _linkA);
    expect(find.text('YouTube link: supported. Tap Choose quality to save the video or just its audio'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Choose quality'));
    await animate(tester);
    expect(source.streamCalls, [_idA]);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);
  });

  test('an expired YouTube file link is explained in plain words', () {
    PlatformInfo.debugIsAndroid = true;
    PlatformInfo.debugIsIOS = false;
    expect(
      formatPlainErrorMessage('http_403', host: 'rr4---sn-abc.googlevideo.com'),
      "YouTube's link to this file has expired. Paste the video link again to download it.",
    );
    expect(formatPlainErrorMessage('http_403', host: 'example.com'), 'The website refused the download. Check the link, then tap Retry.');
    // Plain words and the next step (task: plain Downloads messages).
    expect(formatPlainErrorMessage('insufficient_disk_space'),
        'Your phone is out of space. Free up some space, then tap Retry.');
  });

  test('iPhone: an expired link is only shown when looking it up again failed too', () {
    // setUp made this an iPhone.
    expect(
      formatPlainErrorMessage('http_403', host: 'rr4---sn-abc.googlevideo.com'),
      "YouTube's link to this file has expired and a new one could not be found. "
      'Tap Retry, or paste the video link again.',
    );
    expect(formatPlainErrorMessage('http_410', host: 'rr4---sn-abc.googlevideo.com'), contains('Tap Retry'));
    expect(formatPlainErrorMessage('http_403', host: 'example.com'), 'The website refused the download. Check the link, then tap Retry.');
  });

  // Emulator QA: "Choose quality" with no internet closed without a word.
  group('a failed lookup always leaves a message with Retry', () {
    for (final (name, error, message) in <(String, Object, String)>[
      ('offline', const SocketException('Failed host lookup'), 'No internet connection.'),
      ('too slow', TimeoutException('slow'), YoutubeDirectDownloadFlow.friendlyError(TimeoutException('slow'))),
    ]) {
      testWidgets('iOS direct path, $name: the message stays and Retry looks the link up again', (tester) async {
        var calls = 0;
        source.onStreams = (id) async {
          calls++;
          if (calls == 1) throw error;
          return FakeOnlineSource.sampleStreams;
        };
        final container = makeContainer();
        send(container, _linkA);
        await pumpScreen(tester, container);
        await animate(tester);

        expect(find.text(_dialogText), findsNothing);
        expect(find.text(message), findsOneWidget);
        // Long after a normal snack bar would have gone, it is still there.
        await tester.pump(const Duration(seconds: 30));
        await animate(tester);
        expect(find.text(message), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await animate(tester);
        await animate(tester);
        expect(calls, 2);
        expect(find.byType(FormatSelectionSheet), findsOneWidget);
      });
    }

    testWidgets('Android yt-dlp path, NETWORK_BLOCKED: the message stays with Retry', (tester) async {
      PlatformInfo.debugIsAndroid = true;
      PlatformInfo.debugIsIOS = false;
      backend.onGetInfo = (_) async => throw const ExtractorException('NETWORK_BLOCKED', 'blocked');
      final container = makeContainer(personalTools: true);
      send(container, _linkA);
      await pumpScreen(tester, container);
      await animate(tester);
      const text = 'This network is blocking a secure connection to the site. Try another Wi-Fi or mobile data.';
      expect(find.text(text), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await animate(tester);
      expect(find.text(text), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
