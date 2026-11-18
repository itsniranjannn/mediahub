import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/utils/formatters.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/domain/repositories/video_engine.dart';
import 'package:mediahub/domain/repositories/video_progress_repository.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/video_player_screen.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

/// What the Android player reported on the emulator when the hardware decoder
/// timed out at start (as the notifier receives it: `e.toString()`).
const _decoderFailure =
    'PlatformException(VideoError, Video player had error androidx.media3.exoplayer.'
    'ExoPlaybackException: MediaCodecVideoRenderer error, index=0, format=Format(1, null, '
    'null, video/avc, avc1.64001F, -1, null, [1280, 720, 30.0, ColorInfo(BT709, Limited '
    'range, SDR SMPTE 170M, false, 8bit Luma, 8bit Chroma)], [-1, -1]), '
    'format_supported=YES, null, null)';

const _sourceFailure =
    'PlatformException(VideoError, Video player had error androidx.media3.exoplayer.'
    'ExoPlaybackException: Source error, java.io.FileNotFoundException: '
    '/storage/emulated/0/Movies/Secret_Holiday_Clip.mp4: open failed: ENOENT '
    '(No such file or directory), null)';

const _otherFailure = 'PlatformException(VideoError, Player timed out, null, null)';

const _friendlyDecoder = "This phone couldn't decode this video. Trying again often helps.";
const _friendlySource = "The video file couldn't be opened. It may have been moved or deleted.";
const _friendlyOther = 'Something went wrong while starting this video.';

/// A [VideoEngine] whose [initialize] fails with [failWith] (thrown the way
/// the real engine rethrows a [PlatformException]) or succeeds, and which
/// records what the notifier asked of it. Engines that share [events] write
/// `name.initialize`, `name.dispose` (every call) and `name.disposed` (when
/// the first dispose has finished) to it, in order.
class _ScriptedEngine implements VideoEngine {
  final String? failWith;
  final String name;
  final List<String> events;

  /// dispose() never completes, like a player whose creation failed.
  final bool disposeHangs;
  final List<String> initializedWith = [];
  final List<Duration> seeks = [];
  final List<double> speeds = [];
  int playCalls = 0;
  int disposeCalls = 0;
  bool _initialized = false;
  final _pos = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _err = StreamController<String?>.broadcast();

  _ScriptedEngine({this.failWith, this.name = 'engine', List<String>? events, this.disposeHangs = false})
      : events = events ?? [];

  void emitPosition(Duration position) => _pos.add(position);
  void emitError(String message) => _err.add(message);

  @override
  Future<void> initialize(String uri) async {
    events.add('$name.initialize');
    initializedWith.add(uri);
    final failure = failWith;
    if (failure != null) {
      throw _RawPlatformError(failure);
    }
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isPlaying => playCalls > 0;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 5);
  @override
  double get aspectRatio => 16 / 9;
  @override
  Size get videoSize => const Size(1920, 1080);
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<bool> get isPlayingStream => _playing.stream;
  @override
  Stream<String?> get errorStream => _err.stream;
  @override
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand(key: ValueKey('video-surface'));
  @override
  Future<void> play() async => playCalls++;
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);
  @override
  Future<void> setPlaybackSpeed(double speed) async => speeds.add(speed);

  /// Safe to call twice, like the real engine (the retry disposes it, then
  /// the provider's onDispose does again).
  @override
  Future<void> dispose() async {
    disposeCalls++;
    events.add('$name.dispose');
    if (disposeHangs) return Completer<void>().future;
    if (disposeCalls > 1) return;
    await _pos.close();
    await _playing.close();
    await _err.close();
    events.add('$name.disposed');
  }
}

/// Prints exactly the raw text, like `PlatformException.toString()` does.
class _RawPlatformError implements Exception {
  final String text;
  const _RawPlatformError(this.text);
  @override
  String toString() => text;
}

class _ProgressRepo implements VideoProgressRepository {
  final VideoProgress? saved;
  _ProgressRepo({this.saved});

  @override
  Future<VideoProgress?> getProgress(String mediaId) async => saved;
  @override
  Future<void> saveProgress(VideoProgress progress) async {}
  @override
  Future<void> deleteProgress(String mediaId) async {}
  @override
  Future<List<VideoProgress>> getAllProgress() async => [];
  @override
  Stream<List<VideoProgress>> watchAllProgress() => Stream.value([]);
}

class _LibraryRepo implements LibraryRepository {
  /// Every availability change, as `id:availability`.
  final List<String> availability = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> updateAvailability(String id, MediaAvailability availability) async {
    this.availability.add('$id:${availability.name}');
  }
}

final _item = MediaItem(
  id: 'vid-1',
  title: 'Audit_Long_Tone_5min',
  artist: 'Unknown',
  durationMs: 300000,
  uri: 'file:///storage/emulated/0/Movies/Audit_Long_Tone_5min.mp4',
  mediaType: MediaType.video,
  sizeBytes: 1024,
  dateAdded: DateTime(2026, 1, 1),
);

/// Hands out [engines] in order, one per (re)creation of the engine provider.
class _EngineFactory {
  final List<_ScriptedEngine> engines;
  int created = 0;
  _EngineFactory(this.engines);

  VideoEngine create(Ref ref) {
    final engine = engines[created++];
    ref.onDispose(() => engine.dispose());
    return engine;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _EngineFactory factory, {
  VideoProgress? saved,
  _LibraryRepo? library,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoEngineProvider.overrideWith(factory.create),
        videoProgressRepositoryProvider.overrideWithValue(_ProgressRepo(saved: saved)),
        libraryRepositoryProvider.overrideWithValue(library ?? _LibraryRepo()),
      ],
      child: MaterialApp(theme: theme, home: VideoPlayerScreen(item: _item)),
    ),
  );
  await _settle(tester);
}

/// Lets the async start-up chain finish (pumpAndSettle would spin on the
/// loading indicator).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Every visible string on screen, so raw error text cannot hide anywhere.
Iterable<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

/// Disposes the screen and notifier so their timers are cancelled.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  group('classifyVideoError', () {
    test('decoder, renderer and format errors', () {
      expect(classifyVideoError(_decoderFailure), VideoErrorKind.decoder);
      expect(classifyVideoError('Decoder init failed: OMX.google.h264.decoder'), VideoErrorKind.decoder);
      expect(classifyVideoError('Cannot Decode'), VideoErrorKind.decoder); // iOS AVFoundation
      expect(classifyVideoError('UnrecognizedInputFormatException: no extractor'), VideoErrorKind.decoder);
      expect(classifyVideoError('Unsupported codec hevc'), VideoErrorKind.decoder);
      expect(classifyVideoError('Renderer failed to start'), VideoErrorKind.decoder);
    });

    test('missing file, permission and source errors', () {
      expect(classifyVideoError(_sourceFailure), VideoErrorKind.source);
      expect(classifyVideoError('Cannot open file'), VideoErrorKind.source);
      expect(classifyVideoError('File is corrupt or missing'), VideoErrorKind.source);
      expect(classifyVideoError('SecurityException: Permission denial'), VideoErrorKind.source);
      expect(classifyVideoError('open failed: EACCES (Permission denied)'), VideoErrorKind.source);
      expect(classifyVideoError('ExoPlaybackException: Source error'), VideoErrorKind.source);
      expect(classifyVideoError('The requested URL was not found on this server'), VideoErrorKind.source);
    });

    test('anything else, without false hits on look-alike words', () {
      expect(classifyVideoError(_otherFailure), VideoErrorKind.other);
      expect(classifyVideoError(''), VideoErrorKind.other);
      // "information" contains "format"; "profile" contains "file".
      expect(classifyVideoError('No information available'), VideoErrorKind.other);
      expect(classifyVideoError('Unknown profile'), VideoErrorKind.other);
    });

    test('each kind has its plain message', () {
      expect(VideoErrorKind.decoder.message, _friendlyDecoder);
      expect(VideoErrorKind.source.message, _friendlySource);
      expect(VideoErrorKind.other.message, _friendlyOther);
    });
  });

  group('VideoPlayerScreen error view', () {
    setUp(() async {
      DiagnosticsService.enableDebounce = false;
      await DiagnosticsService.instance.clear();
    });

    for (final (raw, friendly, rawMarkers) in [
      (_decoderFailure, _friendlyDecoder, ['MediaCodec', 'ExoPlaybackException', 'Format(']),
      (_sourceFailure, _friendlySource, ['FileNotFoundException', 'ENOENT', 'Secret_Holiday_Clip']),
      (_otherFailure, _friendlyOther, ['timed out']),
    ]) {
      testWidgets('shows "$friendly" and never the raw exception', (tester) async {
        final factory = _EngineFactory([_ScriptedEngine(failWith: raw)]);
        await _pumpScreen(tester, factory);

        expect(find.text('Unable to play video'), findsOneWidget);
        expect(find.text(friendly), findsOneWidget);
        expect(find.text('Your file is safe.'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
        expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
        expect(find.text('Back to Videos'), findsOneWidget);

        final shown = _visibleTexts(tester).join('\n');
        expect(shown, isNot(contains('PlatformException')));
        expect(shown, isNot(contains('VideoError')));
        for (final marker in rawMarkers) {
          expect(shown, isNot(contains(marker)));
        }

        await _unmount(tester);
      });
    }

    testWidgets('the raw error still reaches the diagnostics log, with paths redacted', (tester) async {
      final factory = _EngineFactory([_ScriptedEngine(failWith: _sourceFailure)]);
      await _pumpScreen(tester, factory);

      final logged = DiagnosticsService.instance.logs.where((l) => l.contains('video_player_error')).toList();
      expect(logged, hasLength(1));
      expect(logged.single, contains('"kind":"source"'));
      expect(logged.single, contains('FileNotFoundException'));
      expect(logged.single, contains('ENOENT'));
      expect(logged.single, isNot(contains('Secret_Holiday_Clip')));

      await _unmount(tester);
    });

    testWidgets('a screen reader is told: one live-region heading with the title and the cause', (tester) async {
      final handle = tester.ensureSemantics();
      final factory = _EngineFactory([_ScriptedEngine(failWith: _decoderFailure)]);
      await _pumpScreen(tester, factory);

      final message = find.semantics.byLabel('Unable to play video\n$_friendlyDecoder\nYour file is safe.');
      expect(message, findsOne);
      expect(message, isSemantics(isLiveRegion: true, isHeader: true));
      // Read once: no second node repeats the title or the cause.
      expect(find.semantics.byPredicate((n) => n.label.contains('Unable to play video')), findsOne);
      expect(find.semantics.byPredicate((n) => n.label.contains(_friendlyDecoder)), findsOne);
      // The buttons stay their own stops.
      for (final label in ['Try again', 'Back to Videos']) {
        expect(find.semantics.byLabel(label), isSemantics(isButton: true, hasTapAction: true), reason: label);
      }

      await _unmount(tester);
      handle.dispose();
    });
  });

  group('Try again', () {
    setUp(() async {
      DiagnosticsService.enableDebounce = false;
      await DiagnosticsService.instance.clear();
      // WakelockPlus talks to the platform once playback starts.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        null,
      );
    });

    testWidgets('clears the error, releases the failed player and starts the same item again from the saved position',
        (tester) async {
      final events = <String>[];
      final failed = _ScriptedEngine(failWith: _decoderFailure, name: 'failed', events: events);
      final fresh = _ScriptedEngine(name: 'fresh', events: events);
      final factory = _EngineFactory([failed, fresh]);
      final library = _LibraryRepo();
      await _pumpScreen(
        tester,
        factory,
        library: library,
        saved: VideoProgress(
          mediaId: _item.id,
          positionMs: 90000,
          durationMs: 300000,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      expect(find.text(_friendlyDecoder), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await _settle(tester);

      expect(find.text('Unable to play video'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);
      // retry() itself disposes the failed player and waits for it to finish
      // before the fresh one starts; the provider then disposes it once more.
      expect(failed.disposeCalls, 2);
      expect(events, ['failed.initialize', 'failed.dispose', 'failed.disposed', 'failed.dispose', 'fresh.initialize']);
      expect(factory.created, 2);
      expect(fresh.initializedWith, [_item.uri]);
      expect(fresh.seeks, [const Duration(seconds: 90)]);
      expect(fresh.playCalls, 1);
      // A decoder failure never marks the file missing, so nothing to undo.
      expect(library.availability, isEmpty);

      await _unmount(tester);
    });

    testWidgets('a failed player whose dispose never finishes holds the retry for 2 s at most', (tester) async {
      final events = <String>[];
      final failed = _ScriptedEngine(failWith: _decoderFailure, name: 'failed', events: events, disposeHangs: true);
      final fresh = _ScriptedEngine(name: 'fresh', events: events);
      final factory = _EngineFactory([failed, fresh]);
      await _pumpScreen(tester, factory);

      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(seconds: 1));
      // Still waiting for the failed player to let go of the decoder.
      expect(factory.created, 1);
      expect(fresh.initializedWith, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(factory.created, 2);
      expect(fresh.initializedWith, [_item.uri]);
      expect(fresh.playCalls, 1);
      expect(events.first, 'failed.initialize');
      expect(events.indexOf('fresh.initialize'), greaterThan(events.indexOf('failed.dispose')));
      expect(find.text('Unable to play video'), findsNothing);
      expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('a file marked missing by the failed attempt is available again once Try again plays it',
        (tester) async {
      final library = _LibraryRepo();
      final factory = _EngineFactory([_ScriptedEngine(failWith: _sourceFailure), _ScriptedEngine()]);
      await _pumpScreen(tester, factory, library: library);
      expect(library.availability, ['${_item.id}:missing']);

      await tester.tap(find.text('Try again'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);
      expect(library.availability, ['${_item.id}:missing', '${_item.id}:available']);

      await _unmount(tester);
    });

    testWidgets('a retry that fails again leaves the file missing', (tester) async {
      final library = _LibraryRepo();
      final factory = _EngineFactory([
        _ScriptedEngine(failWith: _sourceFailure),
        _ScriptedEngine(failWith: _sourceFailure),
      ]);
      await _pumpScreen(tester, factory, library: library);

      await tester.tap(find.text('Try again'));
      await _settle(tester);

      expect(find.text(_friendlySource), findsOneWidget);
      expect(library.availability, everyElement('${_item.id}:missing'));

      await _unmount(tester);
    });

    testWidgets('after an error during playback it resumes from where the video was', (tester) async {
      final first = _ScriptedEngine();
      final second = _ScriptedEngine();
      final factory = _EngineFactory([first, second]);
      await _pumpScreen(tester, factory);
      expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);

      first.emitPosition(const Duration(seconds: 42));
      await tester.pump();
      first.emitError(_decoderFailure);
      await tester.pump();
      // Later updates from the dead player must not wipe the error.
      first.emitPosition(const Duration(seconds: 43));
      await _settle(tester);
      expect(find.text(_friendlyDecoder), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await _settle(tester);

      expect(find.text('Unable to play video'), findsNothing);
      expect(second.seeks, [const Duration(seconds: 42)]);
      expect(factory.created, 2);

      await _unmount(tester);
    });

    testWidgets('double taps start only one retry', (tester) async {
      final factory = _EngineFactory([
        _ScriptedEngine(failWith: _decoderFailure),
        _ScriptedEngine(),
        _ScriptedEngine(),
      ]);
      await _pumpScreen(tester, factory);

      final button = find.text('Try again');
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await _settle(tester);

      expect(factory.created, 2);
      expect(find.text('Unable to play video'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('a retry that fails again shows the error again and can be retried', (tester) async {
      final factory = _EngineFactory([
        _ScriptedEngine(failWith: _decoderFailure),
        _ScriptedEngine(failWith: _decoderFailure),
        _ScriptedEngine(),
      ]);
      await _pumpScreen(tester, factory);

      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text(_friendlyDecoder), findsOneWidget);
      expect(factory.created, 2);
      // Each failed attempt is logged once.
      expect(
        DiagnosticsService.instance.logs.where((l) => l.contains('video_player_error')),
        hasLength(2),
      );

      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Unable to play video'), findsNothing);
      expect(factory.created, 3);

      await _unmount(tester);
    });
  });

  // DESIGN.md 7.9 and 8.2: the video stage is ink in both themes.
  group('the stage', () {
    const ink = AppPalette.dark;
    const wakelock = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

    setUp(() {
      DiagnosticsService.enableDebounce = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        wakelock,
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(wakelock, null);
    });

    testWidgets('in the light theme: dark palette, light bar icons, a Volt play disc, the title in Anek',
        (tester) async {
      await _pumpScreen(tester, _EngineFactory([_ScriptedEngine()]), theme: AppTheme.lightTheme);
      expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);

      expect(Theme.of(tester.element(find.byType(Slider))).brightness, Brightness.dark);
      final bars = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(bars.value, AppTheme.barsOnInk);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, const Color(0xFF000000));

      expect(find.byType(VoltDisc), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);

      // The video's own name: Anek, two lines, broken after "_", read whole.
      final title = tester.widget<Text>(find.text(breakableTitle(_item.title)));
      expect(title.style!.fontFamily, 'AnekWide');
      expect(title.style!.letterSpacing, 0);
      expect(title.maxLines, 2);
      expect(title.semanticsLabel, _item.title);
      expect(title.style!.color, ink.onOverlay);

      // The times in DM Mono.
      expect(tester.widget<Text>(find.text('0:00')).style!.fontFamily, 'DMMono');
      expect(tester.widget<Text>(find.text('5:00')).style!.fontFamily, 'DMMono');

      await _unmount(tester);
    });

    testWidgets('locked: a Volt lock on the ink overlay chip (was Volt on a Volt fill)', (tester) async {
      await _pumpScreen(tester, _EngineFactory([_ScriptedEngine()]));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock controls'));
      await tester.pumpAndSettle();

      final lock = tester.widget<IconButton>(
        find.ancestor(of: find.byTooltip('Unlock Controls'), matching: find.byType(IconButton)).first,
      );
      expect(lock.style!.backgroundColor!.resolve(const {}), ink.overlay);
      expect(lock.style!.foregroundColor!.resolve(const {}), ink.primary);

      await tester.tap(find.byTooltip('Unlock Controls'));
      await tester.pump();
      expect(find.byTooltip('Unlock Controls'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the error view keeps the dark palette in the light theme', (tester) async {
      await _pumpScreen(
        tester,
        _EngineFactory([_ScriptedEngine(failWith: _decoderFailure)]),
        theme: AppTheme.lightTheme,
      );
      final heading = tester.widget<Text>(find.text('Unable to play video'));
      expect(heading.style!.color, ink.textPrimary);
      expect(heading.style!.fontFamily, 'Unbounded', reason: 'an app string: the heading voice');
      expect(tester.widget<Text>(find.text(_friendlyDecoder)).style!.color, ink.textSecondary);
      expect(tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded)).color, ink.error);
      await _unmount(tester);
    });
  });
}
