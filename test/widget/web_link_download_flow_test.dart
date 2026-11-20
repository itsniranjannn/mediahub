import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/downloads/extractor_download_runner.dart';
import 'package:mediahub/features/downloads/download_providers.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/web_link_download_flow.dart';
import 'package:mediahub/personal/extractor_auto_updater.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/extractor_errors.dart';
import 'package:mediahub/personal/format_options.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';

import '../unit/fake_extractor_backend.dart';

/// Fake backend whose `getInfo` answer each test scripts through [onGetInfo]
/// (by default the stock sample video).
class _ScriptedBackend extends FakeExtractorBackend {
  final List<String> infoCalls = [];
  Future<ExtractorMetadata> Function(String url)? onGetInfo;

  @override
  Future<ExtractorMetadata> getInfo(String url, {String? requestId}) {
    infoCalls.add(url);
    final handler = onGetInfo;
    // Called without an await on purpose: a handler may throw synchronously.
    return handler != null ? handler(url) : super.getInfo(url);
  }
}

/// Records what the flow asks to queue; nothing touches the database.
class _FakeRunner extends Fake implements ExtractorDownloadRunner {
  final List<({String pageUrl, FormatChoice choice})> enqueued = [];

  @override
  Future<String> enqueue({
    required ExtractorMetadata meta,
    required String pageUrl,
    required FormatChoice choice,
  }) async {
    enqueued.add((pageUrl: pageUrl, choice: choice));
    return 'x1';
  }
}

/// Queue coordinator that only counts how often it was poked.
class _FakeQueueCoordinator extends DownloadQueueCoordinatorNotifier {
  int triggers = 0;

  @override
  void build() {}

  @override
  Future<void> trigger() async => triggers++;
}

const _dialogText = 'Finding available qualities...';
const _timeoutText = 'This link is taking too long. Try again later.';
final _videoUri = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

void main() {
  late _ScriptedBackend backend;
  late _FakeRunner runner;
  late _FakeQueueCoordinator coordinator;
  late bool flowDone;
  late int queuedCallbacks;

  setUp(() {
    // Lookups are logged; no 3 s write timer may outlive a widget test.
    DiagnosticsService.enableDebounce = false;
    // Not Android: the notification permission check is skipped.
    PlatformInfo.debugIsAndroid = false;
    PlatformInfo.debugIsIOS = false;
    backend = _ScriptedBackend();
    runner = _FakeRunner();
    coordinator = _FakeQueueCoordinator();
    flowDone = false;
    queuedCallbacks = 0;
  });
  tearDown(PlatformInfo.resetForTests);

  /// A phone-width surface tall enough to show the whole quality sheet.
  void usePhone(WidgetTester tester) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(412 * 2, 1600 * 2);
    addTearDown(tester.view.reset);
  }

  /// A screen with one "Download" button that starts the flow. When
  /// [showCaller] is given, flipping it to false removes that screen's
  /// widget (and so its context) from the tree.
  Future<void> pumpHost(
    WidgetTester tester, {
    ValueNotifier<bool>? showCaller,
    GlobalKey<NavigatorState>? navigatorKey,
    bool noticeAgreed = false,
    Future<void> Function()? onEngineUnavailable,
    Future<void> Function()? onOtherSite,
    Uri? uri,
    ExtractorAutoUpdater? updater,
  }) async {
    usePhone(tester);
    final caller = Consumer(
      builder: (context, ref, _) => Center(
        child: ElevatedButton(
          onPressed: () => unawaited(
            WebLinkDownloadFlow.start(
              context,
              ref,
              uri ?? _videoUri,
              onQueued: () => queuedCallbacks++,
              onEngineUnavailable: onEngineUnavailable,
              onOtherSite: onOtherSite,
            ).then((_) => flowDone = true),
          ),
          child: const Text('Download'),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extractorBackendProvider.overrideWithValue(backend),
          extractorDownloadRunnerProvider.overrideWithValue(runner),
          downloadQueueCoordinatorProvider.overrideWith(() => coordinator),
          if (noticeAgreed) downloadNoticeAgreedProvider.overrideWithBuild((ref, notifier) => true),
          if (updater != null) extractorAutoUpdaterProvider.overrideWithValue(updater),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: showCaller == null
                ? caller
                : ValueListenableBuilder<bool>(
                    valueListenable: showCaller,
                    builder: (context, show, child) => show ? caller : const SizedBox.shrink(),
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets dialogs, sheets and snack bars animate in or out. (No pumpAndSettle:
  /// the loading dialog's spinner never stops.)
  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapDownload(WidgetTester tester) async {
    await tester.tap(find.text('Download'));
    await animate(tester);
  }

  /// Nothing was queued and no sheet or message appeared.
  void expectNothingHappened() {
    expect(find.byType(FormatSelectionSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(runner.enqueued, isEmpty);
    expect(coordinator.triggers, 0);
    expect(queuedCallbacks, 0);
  }

  testWidgets('Cancel closes a lookup that never finishes and nothing is queued', (tester) async {
    backend.onGetInfo = (_) => Completer<ExtractorMetadata>().future; // never completes
    await pumpHost(tester);
    await tapDownload(tester);

    expect(find.text(_dialogText), findsOneWidget);
    expect(find.text('youtube.com'), findsOneWidget); // the site being read
    expect(backend.infoCalls, [_videoUri.toString()]);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await animate(tester);

    expect(find.text(_dialogText), findsNothing);
    expect(flowDone, isTrue, reason: 'start() returns as soon as the user cancels');
    expect(find.text('Download'), findsOneWidget, reason: 'the calling screen stays open');
    expect(backend.cancelledInfo, hasLength(1), reason: 'yt-dlp is told to stop the abandoned lookup');
    expectNothingHappened();

    // The abandoned lookup's timeout fires later: still no message.
    await tester.pump(WebLinkDownloadFlow.infoTimeout + const Duration(seconds: 1));
    await animate(tester);
    expectNothingHappened();
  });

  testWidgets('A result that arrives after Cancel never opens the quality sheet', (tester) async {
    final info = Completer<ExtractorMetadata>();
    backend.onGetInfo = (_) => info.future;
    await pumpHost(tester);
    await tapDownload(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await animate(tester);
    expect(find.text(_dialogText), findsNothing);

    info.complete(FakeExtractorBackend.sampleMetadata());
    await animate(tester);

    expect(find.text('Download'), findsOneWidget);
    expectNothingHappened();
  });

  testWidgets('An error that arrives after Cancel is ignored', (tester) async {
    final info = Completer<ExtractorMetadata>();
    backend.onGetInfo = (_) => info.future;
    await pumpHost(tester);
    await tapDownload(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await animate(tester);

    info.completeError(const ExtractorException('NETWORK_ERROR', 'offline'));
    await animate(tester);

    expectNothingHappened();
  });

  testWidgets('The system back gesture acts like Cancel', (tester) async {
    final info = Completer<ExtractorMetadata>();
    backend.onGetInfo = (_) => info.future;
    await pumpHost(tester);
    await tapDownload(tester);
    expect(find.text(_dialogText), findsOneWidget);

    await tester.binding.handlePopRoute();
    await animate(tester);

    expect(find.text(_dialogText), findsNothing);
    expect(flowDone, isTrue);
    expect(find.text('Download'), findsOneWidget, reason: 'back only closed the dialog');

    info.complete(FakeExtractorBackend.sampleMetadata());
    await animate(tester);
    expectNothingHappened();
  });

  testWidgets('A lookup that takes longer than 90 s gives up with a friendly message', (tester) async {
    backend.onGetInfo = (_) => Completer<ExtractorMetadata>().future; // stuck yt-dlp
    await pumpHost(tester);
    await tapDownload(tester);

    await tester.pump(const Duration(seconds: 89));
    expect(find.text(_dialogText), findsOneWidget, reason: 'still waiting before the timeout');
    expect(flowDone, isFalse);

    await tester.pump(const Duration(seconds: 2));
    await animate(tester);

    expect(find.text(_dialogText), findsNothing);
    expect(find.text(_timeoutText), findsOneWidget);
    expect(flowDone, isTrue);
    expect(find.byType(FormatSelectionSheet), findsNothing);
    expect(runner.enqueued, isEmpty);
    expect(backend.cancelledInfo, hasLength(1), reason: 'the stuck lookup is stopped too');
  });

  for (final (code, message) in [
    ('PLAYLIST_NOT_SUPPORTED', "Playlists and channels can't be downloaded. Open a single video link instead."),
    ('LIVE_NOT_SUPPORTED', "Live streams can't be downloaded."),
    ('INFO_TIMEOUT', _timeoutText), // the native watchdog gave up first
  ]) {
    testWidgets('$code closes the dialog and explains why', (tester) async {
      backend.onGetInfo = (_) async => throw ExtractorException(code, 'native message');
      await pumpHost(tester);
      await tapDownload(tester);

      expect(find.text(_dialogText), findsNothing);
      expect(find.text(message), findsOneWidget);
      expect(find.byType(FormatSelectionSheet), findsNothing);
      expect(runner.enqueued, isEmpty);
    });
  }

  for (final error in <Object>[
    const ExtractorException('INIT_FAILED', 'no python'),
    const ExtractorException('EXTRACTION_FAILED', 'site changed'),
    UnsupportedError('no extractor'),
  ]) {
    testWidgets('yt-dlp unable to run ($error) hands over to the fallback instead of an error', (tester) async {
      backend.onGetInfo = (_) async => throw error;
      var fallbacks = 0;
      await pumpHost(tester, onEngineUnavailable: () async => fallbacks++);
      await tapDownload(tester);

      expect(fallbacks, 1);
      expect(find.text(_dialogText), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(flowDone, isTrue);
    });
  }

  for (final code in ['NETWORK_ERROR', 'PRIVATE_CONTENT', 'LIVE_NOT_SUPPORTED', 'INFO_TIMEOUT']) {
    testWidgets('$code is about the link, not the engine: the error shows and no fallback runs', (tester) async {
      backend.onGetInfo = (_) async => throw ExtractorException(code, 'native message');
      var fallbacks = 0;
      await pumpHost(tester, onEngineUnavailable: () async => fallbacks++);
      await tapDownload(tester);

      expect(fallbacks, 0);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  }

  testWidgets('A backend that throws synchronously still closes the dialog', (tester) async {
    backend.onGetInfo = (_) => throw StateError('boom');
    await pumpHost(tester);
    await tapDownload(tester);

    expect(find.text(_dialogText), findsNothing);
    expect(find.text('Could not read this link. Please try again.'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget, reason: 'only the dialog was closed');
    expect(flowDone, isTrue);
  });

  testWidgets('If the calling screen goes away, the dialog still closes and nothing follows',
      (tester) async {
    final info = Completer<ExtractorMetadata>();
    backend.onGetInfo = (_) => info.future;
    final showCaller = ValueNotifier<bool>(true);
    addTearDown(showCaller.dispose);
    await pumpHost(tester, showCaller: showCaller);
    await tapDownload(tester);

    showCaller.value = false; // the screen that started the flow is gone
    await tester.pump();
    expect(find.text(_dialogText), findsOneWidget);

    info.complete(FakeExtractorBackend.sampleMetadata());
    await animate(tester);

    expect(find.text(_dialogText), findsNothing);
    expect(flowDone, isTrue);
    expectNothingHappened();
  });

  /// Starts a lookup, opens 'Other screen' above the dialog (as the video
  /// player does on the root navigator), then lets the lookup end via [finish].
  Future<GlobalKey<NavigatorState>> coverDialogThenFinish(
    WidgetTester tester,
    void Function(Completer<ExtractorMetadata> info) finish,
  ) async {
    final info = Completer<ExtractorMetadata>();
    backend.onGetInfo = (_) => info.future;
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpHost(tester, navigatorKey: navigatorKey);
    await tapDownload(tester);

    unawaited(navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other screen'))),
    ));
    await animate(tester);

    finish(info);
    await animate(tester);
    return navigatorKey;
  }

  testWidgets('Closing the dialog never pops a route that was pushed above it', (tester) async {
    final navigatorKey = await coverDialogThenFinish(
      tester,
      (info) => info.complete(FakeExtractorBackend.sampleMetadata()),
    );

    expect(find.text(_dialogText), findsNothing);
    expect(find.text('Other screen'), findsOneWidget);
    // The user moved on: the lookup is abandoned, so the quality sheet is not
    // opened over (or hidden behind) the unrelated screen.
    expect(flowDone, isTrue);
    expectNothingHappened();

    // Going back shows the calling screen, with no stale dialog or sheet.
    navigatorKey.currentState!.pop();
    await animate(tester);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text(_dialogText), findsNothing);
    expectNothingHappened();
  });

  testWidgets('A lookup that fails while another screen is on top shows no message',
      (tester) async {
    await coverDialogThenFinish(
      tester,
      (info) => info.completeError(const ExtractorException('NETWORK_ERROR', 'offline')),
    );

    expect(find.text(_dialogText), findsNothing);
    expect(find.text('Other screen'), findsOneWidget);
    expect(flowDone, isTrue);
    expectNothingHappened();
  });

  testWidgets('A quick answer opens the quality sheet and the picked quality is queued',
      (tester) async {
    await pumpHost(tester, noticeAgreed: true);
    await tapDownload(tester);

    expect(find.text(_dialogText), findsNothing);
    expect(find.byType(FormatSelectionSheet), findsOneWidget);

    await tester.tap(find.text('720p'));
    await animate(tester);

    expect(find.byType(FormatSelectionSheet), findsNothing);
    expect(runner.enqueued, hasLength(1));
    expect(runner.enqueued.single.pageUrl, _videoUri.toString());
    expect(runner.enqueued.single.choice.id, 'v720');
    expect(coordinator.triggers, 1);
    expect(queuedCallbacks, 1);
    expect(find.text('Added to Downloads: Sample Test Video (720p)'), findsOneWidget);
    expect(flowDone, isTrue);
  });

  group('Spotify (SEC-14)', () {
    const message = "Spotify songs are protected and can't be saved. Search for the song in the Online tab instead.";

    for (final link in [
      'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
      'https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3',
      'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      'https://open.spotify.com/intl-de/track/4cOdK2wGLETKBW3PvgPWqT',
    ]) {
      testWidgets('$link is refused at once, without a lookup', (tester) async {
        await pumpHost(tester, uri: Uri.parse(link));
        await tapDownload(tester);
        expect(find.text(_dialogText), findsNothing);
        expect(backend.infoCalls, isEmpty);
        expect(find.text(message), findsOneWidget);
        expect(runner.enqueued, isEmpty);
        expect(flowDone, isTrue);
      });
    }

    testWidgets('a podcast episode is still looked up', (tester) async {
      final episode = Uri.parse('https://open.spotify.com/episode/512ojhOuo1ktJprKbVcKyQ');
      await pumpHost(tester, uri: episode, noticeAgreed: true);
      await tapDownload(tester);
      expect(backend.infoCalls, [episode.toString()]);
      expect(find.text(message), findsNothing);
    });
  });

  group('a site yt-dlp may not read (any other https link)', () {
    final file = Uri.parse('https://cdn.example.com/media/song.mp3');

    testWidgets('goes to the direct-link check instead, without a lookup', (tester) async {
      var others = 0;
      await pumpHost(tester, uri: file, onOtherSite: () async => others++);
      await tapDownload(tester);
      expect(others, 1);
      expect(backend.infoCalls, isEmpty);
      expect(find.text(_dialogText), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(flowDone, isTrue);
    });

    testWidgets('without that, says the site is not supported (still no lookup)', (tester) async {
      await pumpHost(tester, uri: file);
      await tapDownload(tester);
      expect(backend.infoCalls, isEmpty);
      expect(find.text(ExtractorErrors.hostNotAllowed), findsOneWidget);
    });

    testWidgets('the native side refusing the host also goes to the direct-link check', (tester) async {
      backend.onGetInfo = (_) async => throw const ExtractorException('HOST_NOT_ALLOWED', 'not allowed');
      var others = 0;
      await pumpHost(tester, onOtherSite: () async => others++);
      await tapDownload(tester);
      expect(others, 1);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('yt-dlp out of date (Android)', () {
    setUp(() => PlatformInfo.debugIsAndroid = true);

    testWidgets('a lookup that fails because the site changed updates yt-dlp and reads the link again',
        (tester) async {
      var calls = 0;
      backend.onGetInfo = (_) async {
        calls++;
        if (calls == 1) throw const ExtractorException('EXTRACTION_FAILED', 'Unable to extract');
        return FakeExtractorBackend.sampleMetadata();
      };
      final updater = ExtractorAutoUpdater(backend: backend, store: SettingsStore.forTesting());
      addTearDown(updater.dispose);
      await pumpHost(tester, updater: updater);
      await tapDownload(tester);
      await animate(tester);

      expect(backend.updateCalls, 1);
      expect(backend.infoCalls, hasLength(2));
      expect(find.byType(FormatSelectionSheet), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('WebLinkDownloadFlow.lookupWithUpdate', () {
    late ExtractorAutoUpdater updater;

    setUp(() {
      updater = ExtractorAutoUpdater(backend: backend, store: SettingsStore.forTesting(), enabled: () => true);
    });
    tearDown(() => updater.dispose());

    Future<ExtractorMetadata> lookup({bool abandoned = false, bool downloadsRunning = false}) =>
        WebLinkDownloadFlow.lookupWithUpdate(
          backend: backend,
          updater: updater,
          uri: _videoUri,
          requestId: 'info1',
          abandoned: () => abandoned,
          downloadsRunning: downloadsRunning,
        );

    void failFirst(String code) {
      var calls = 0;
      backend.onGetInfo = (_) async {
        calls++;
        if (calls == 1) throw ExtractorException(code, 'native');
        return FakeExtractorBackend.sampleMetadata();
      };
    }

    test('no update needed: one read', () async {
      expect((await lookup()).title, 'Sample Test Video');
      expect(backend.updateCalls, 0);
      expect(backend.infoCalls, hasLength(1));
    });

    for (final code in ['EXTRACTION_FAILED', 'FORMAT_UNAVAILABLE', 'BOT_CHECK']) {
      test('$code: update, then a second read', () async {
        failFirst(code);
        expect((await lookup()).title, 'Sample Test Video');
        expect(backend.updateCalls, 1);
        expect(backend.infoCalls, hasLength(2));
      });
    }

    for (final code in ['PRIVATE_CONTENT', 'AGE_RESTRICTED', 'UNAVAILABLE', 'NETWORK_ERROR', 'INIT_FAILED']) {
      test('$code: no update, the error stands', () async {
        failFirst(code);
        await expectLater(lookup(), throwsA(isA<ExtractorException>().having((e) => e.code, 'code', code)));
        expect(backend.updateCalls, 0);
      });
    }

    test('yt-dlp already the newest: the first error stands (no second read)', () async {
      final b = _UpToDateBackend();
      final u = ExtractorAutoUpdater(backend: b, store: SettingsStore.forTesting(), enabled: () => true);
      addTearDown(u.dispose);
      b.onGetInfo = (_) async => throw const ExtractorException('EXTRACTION_FAILED', 'x');
      await expectLater(
        WebLinkDownloadFlow.lookupWithUpdate(
          backend: b,
          updater: u,
          uri: _videoUri,
          requestId: 'info1',
          abandoned: () => false,
        ),
        throwsA(isA<ExtractorException>()),
      );
      expect(b.infoCalls, hasLength(1));
    });

    test('closed by the user or downloads running: no update', () async {
      failFirst('EXTRACTION_FAILED');
      await expectLater(lookup(abandoned: true), throwsA(isA<ExtractorException>()));
      failFirst('EXTRACTION_FAILED');
      await expectLater(lookup(downloadsRunning: true), throwsA(isA<ExtractorException>()));
      expect(backend.updateCalls, 0);
    });
  });
}

class _UpToDateBackend extends _ScriptedBackend {
  @override
  Future<String> update() async {
    updateCalls++;
    return 'ALREADY_UP_TO_DATE';
  }
}
