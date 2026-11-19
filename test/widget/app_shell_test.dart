import 'dart:async';

import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/app/app.dart';
import 'package:mediahub/app/app_shell.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:mediahub/core/app_config.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/shared/widgets/ink_dock.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart' show databaseProvider;
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/online/online_screen.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:go_router/go_router.dart';
import '../unit/permission_service_test.dart';
import 'online_fakes.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class FakeAudioSource extends Fake implements AudioSource {}
class FakePlaybackState extends Fake implements domain.PlaybackState {}
class MockPlaybackRepository extends Mock implements PlaybackRepository {}

void main() {
  setUpAll(() {
    DiagnosticsService.enableDebounce = false;
    registerFallbackValue(Duration.zero);
    registerFallbackValue(FakeAudioSource());
    registerFallbackValue(LoopMode.off);
    registerFallbackValue(FakePlaybackState());
  });

  // The Downloads tab only exists on mobile; pretend to be Android on the test host.
  setUp(() => PlatformInfo.debugIsAndroid = true);
  tearDown(PlatformInfo.resetForTests);

  testWidgets('MediaHubApp launches and navigates through tabs',
      (WidgetTester tester) async {
    final mockPlayer = MockAudioPlayer();
    when(() => mockPlayer.playbackEventStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.playerStateStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.currentIndexStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.positionStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.durationStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.playing).thenReturn(false);
    when(() => mockPlayer.processingState).thenReturn(ProcessingState.ready);
    when(() => mockPlayer.position).thenReturn(Duration.zero);
    when(() => mockPlayer.bufferedPosition).thenReturn(Duration.zero);
    when(() => mockPlayer.speed).thenReturn(1.0);
    when(() => mockPlayer.duration).thenReturn(null);
    when(() => mockPlayer.currentIndex).thenReturn(null);
    when(() => mockPlayer.shuffleModeEnabled).thenReturn(false);
    when(() => mockPlayer.hasNext).thenReturn(false);
    when(() => mockPlayer.hasPrevious).thenReturn(false);
    when(() => mockPlayer.setShuffleModeEnabled(any())).thenAnswer((_) async {});
    when(() => mockPlayer.setLoopMode(any())).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});

    final db = AppDatabase(NativeDatabase.memory());
    final handler = MusicAudioHandler(player: mockPlayer);
    final mockRepo = MockPlaybackRepository();
    // Platform views do not run in flutter test: the Online tab gets a fake WebView.
    final web = FakeOnlineWebView();
    when(() => mockRepo.loadLastPlaybackState()).thenAnswer((_) async => null);
    when(() => mockRepo.savePlaybackState(any())).thenAnswer((_) async {});

    // The phone is in light mode.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          databaseProvider.overrideWithValue(db),
          audioHandlerProvider.overrideWithValue(handler),
          playbackRepositoryProvider.overrideWithValue(mockRepo),
          mediaPermissionServiceProvider.overrideWithValue(MockMediaPermissionService()),
          onlineWebViewBuilderProvider.overrideWithValue(web.builder),
          onlineAssetsProvider.overrideWith((ref) async => fakeOnlineAssets),
          androidSdkIntProvider.overrideWith((ref) async => null),
        ],
        child: const MediaHubApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(AppConfig.appName), findsWidgets);

    // The app follows the phone (Settings → Appearance defaults to System):
    // paper here, while the mini player and the nav stay ink in both themes.
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme, same(AppTheme.lightTheme));
    expect(app.darkTheme, same(AppTheme.darkTheme));
    expect(Theme.of(tester.element(find.text(AppConfig.appName).first)).brightness, Brightness.light);
    final dock = find.byKey(const ValueKey('mini_player_slot'));
    expect(Theme.of(tester.element(dock)).brightness, Brightness.dark);
    final dockBars = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.ancestor(of: dock, matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).first,
    );
    expect(dockBars.value, AppTheme.barsOnInk);

    // Tap Music tab
    await tester.tap(find.text('Music'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The Music tab's copy belongs to the library package (old or new wording).
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Permission Required' || w.data == 'Allow access to your music'),
      ),
      findsOneWidget,
    );

    // Tap Videos tab: the friendly sentence-case copy (SEC-12).
    await tester.tap(find.text('Videos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Allow access to your videos'), findsOneWidget);
    expect(find.text('Allow access'), findsOneWidget);
    expect(find.text('Permission Required'), findsNothing);

    // Tap Downloads tab
    await tester.tap(find.text('Downloads'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No downloads yet'), findsOneWidget);

    // Tap the Online tab (YouTube in a WebView; "Explore" is gone)
    expect(find.text('Explore'), findsNothing);
    await tester.tap(find.text('Online'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(OnlineScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('fake_webview')), findsOneWidget);
    expect(find.byTooltip('More options'), findsOneWidget);
    expect(web.mounts, 1);

    // The page is kept alive across tab switches (the shell's indexed stack).
    await tester.tap(find.text('Music'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Online'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(web.mounts, 1, reason: 'the WebView must not be recreated');

    // Old "/explore" links land on Online.
    GoRouter.of(tester.element(find.byType(OnlineScreen))).go('/explore');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(OnlineScreen), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.byType(OnlineScreen))).routerDelegate.currentConfiguration.uri.path,
      '/online',
    );

    // Settings now opens from the gear in the Home header
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Audio & headset'), findsOneWidget);
    expect(find.text('Online'), findsWidgets); // Settings → Online card
    expect(find.text('Diagnostics log'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);

    // unmount so database streams are cancelled before the test ends
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  // DESIGN.md 7.7: the nav half of the Ink Dock, on a stand-in router.
  group('the Ink Dock nav', () {
    DownloadEntry download(String id, DownloadTaskState state) => DownloadEntry(
          id: id,
          url: 'https://example.com/$id.mp4',
          host: 'example.com',
          displayName: 'Item $id',
          fileName: '$id.mp4',
          state: state.name,
          receivedBytes: 0,
          supportsRange: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          engine: 'http',
        );

    Future<GoRouter> pumpShell(
      WidgetTester tester, {
      List<DownloadEntry> downloads = const [],
      double width = 360,
      double textScale = 1,
      MediaItem? playing,
      ExternalMediaSnapshot? external,
      bool reduceMotion = false,
      MusicAudioHandler? handler,
    }) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (textScale != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => AppShell(navigationShell: shell),
            branches: [
              for (final name in ['home', 'music', 'videos', 'online', 'downloads'])
                StatefulShellBranch(
                  routes: [GoRoute(path: '/$name', builder: (context, state) => Center(child: Text('page $name')))],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackNotifierProvider.overrideWith(_NothingPlaying.new),
            downloadsStreamProvider.overrideWith((ref) => Stream.value(downloads)),
            if (playing != null) ...[
              currentMediaItemProvider.overrideWith((ref) => playing),
              isPlayingProvider.overrideWith((ref) => true),
              throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 15))),
            ],
            if (external != null) externalMediaProvider.overrideWith(() => _FixedExternal(external)),
            if (handler != null) audioHandlerProvider.overrideWithValue(handler),
          ],
          // The phone is in light mode: the dock stays ink.
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
            builder: reduceMotion
                ? (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(disableAnimations: true),
                      child: child!,
                    )
                : null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return router;
    }

    Rect indicator(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('nav_indicator')));

    testWidgets("the music player's own messages show as a snackbar, each time", (tester) async {
      final player = MockAudioPlayer();
      when(() => player.playbackEventStream).thenAnswer((_) => const Stream.empty());
      when(() => player.playerStateStream).thenAnswer((_) => const Stream.empty());
      when(() => player.currentIndexStream).thenAnswer((_) => const Stream.empty());
      when(() => player.positionStream).thenAnswer((_) => const Stream.empty());
      when(() => player.durationStream).thenAnswer((_) => const Stream.empty());
      when(() => player.dispose()).thenAnswer((_) async {});
      final handler = _MessagesHandler(player);
      addTearDown(handler.dispose);
      await pumpShell(tester, handler: handler);

      handler.messages.add('''Can't play "Song 2"''');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('''Can't play "Song 2"'''), findsOneWidget);

      // The same message again (the same song failing later) shows again.
      ScaffoldMessenger.of(tester.element(find.text('page home'))).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.text('''Can't play "Song 2"'''), findsNothing);
      handler.messages.add('''Can't play "Song 2"''');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('''Can't play "Song 2"'''), findsOneWidget);
    });

    testWidgets('a 56x32 Volt pill under the filled icon slides to the tapped tab', (tester) async {
      await pumpShell(tester);
      expect(tester.takeException(), isNull);
      expect(indicator(tester).size, const Size(56, 32));
      expect(indicator(tester).center.dx, closeTo(tester.getCenter(find.byIcon(Icons.home_rounded)).dx, 0.5));
      final pill = tester.widget<DecoratedBox>(find.byKey(const ValueKey('nav_indicator')));
      expect((pill.decoration as ShapeDecoration).color, AppPalette.dark.navIndicator);

      // Selected: filled ink icon, onDock label. Others: outline icon, onDockMuted.
      expect(tester.widget<Icon>(find.byIcon(Icons.home_rounded)).color, AppPalette.dark.onNavIndicator);
      expect(tester.widget<Icon>(find.byIcon(Icons.music_note_outlined)).color, AppPalette.dark.onDockMuted);
      expect(tester.widget<Text>(find.text('Home')).style!.color, AppPalette.dark.onDock);
      expect(tester.widget<Text>(find.text('Music')).style!.color, AppPalette.dark.onDockMuted);
      expect(Theme.of(tester.element(find.text('Home'))).brightness, Brightness.dark);

      await tester.tap(find.text('Music'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final midway = indicator(tester).center.dx;
      await tester.pumpAndSettle();
      final music = tester.getCenter(find.byIcon(Icons.music_note_rounded)).dx;
      expect(indicator(tester).center.dx, closeTo(music, 0.5));
      expect(midway, inExclusiveRange(tester.getCenter(find.byIcon(Icons.home_outlined)).dx, music + 0.01),
          reason: 'it slides');
      expect(find.text('page music'), findsOneWidget);
    });

    testWidgets('each tab is one node, "<label> Tab", with the selected state', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpShell(tester);
      expect(find.semantics.byLabel('Home Tab'), isSemantics(isButton: true, isSelected: true, hasTapAction: true));
      expect(find.semantics.byLabel('Music Tab'), isSemantics(isButton: true, isSelected: false, hasTapAction: true));
      handle.dispose();
    });

    testWidgets('the Downloads tab shows an Ice dot with the running count', (tester) async {
      await pumpShell(tester, downloads: [
        download('a', DownloadTaskState.downloading),
        download('b', DownloadTaskState.queued),
        download('c', DownloadTaskState.completed),
        download('d', DownloadTaskState.failed),
      ]);
      final count = find.text('2');
      expect(count, findsOneWidget);
      expect(tester.widget<Text>(count).style!.color, AppPalette.dark.onAccent);
      expect(tester.widget<Text>(count).style!.fontFamily, 'DMMono');
      final dot = tester.widget<Container>(find.ancestor(of: count, matching: find.byType(Container)).first);
      expect((dot.decoration! as ShapeDecoration).color, AppPalette.dark.accent);
      expect(tester.getSize(find.ancestor(of: count, matching: find.byType(Container)).first).height, 16);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpShell(tester, downloads: [download('c', DownloadTaskState.completed)]);
      expect(find.text('1'), findsNothing, reason: 'nothing running: no dot');
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('five labels hold at 1.3x text on $width dp', (tester) async {
        await pumpShell(tester, width: width, textScale: 1.3);
        expect(tester.takeException(), isNull);
        for (final label in ['Home', 'Music', 'Videos', 'Online', 'Downloads']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.width, lessThanOrEqualTo(width / 5), reason: label);
        }
      });
    }

    // The owner: "don't keep that playing menu on the Online section and
    // Videos section". The mini player folds away there and comes back on
    // the other tabs; the music itself is not touched.
    group('the mini player steps aside on Videos and Online', () {
      final song = MediaItem(
        id: 'song_1',
        uri: 'file:///song.mp3',
        mediaType: MediaType.audio,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        durationMs: 354000,
        sizeBytes: 8000000,
        dateAdded: DateTime(2026),
      );

      double slot(WidgetTester tester) => tester.getSize(find.byKey(const ValueKey('mini_player_fold'))).height;
      double page(WidgetTester tester, String name) =>
          tester.getSize(find.ancestor(of: find.text('page $name'), matching: find.byType(Center)).first).height;
      bool miniPlayerHittable(WidgetTester tester) =>
          find.text('Bohemian Rhapsody').hitTestable().evaluate().isNotEmpty;

      Future<void> tapTab(WidgetTester tester, String label) async {
        await tester.tap(find.text(label));
        await tester.pump();
      }

      testWidgets('hidden on Videos and Online, back on the other tabs', (tester) async {
        await pumpShell(tester, playing: song);
        // The row is at least 64 dp (it grows with the text).
        final full = slot(tester);
        expect(full, greaterThanOrEqualTo(InkDock.miniPlayerHeight));
        expect(miniPlayerHittable(tester), isTrue);
        final homeHeight = page(tester, 'home');

        for (final (tab, hidden) in [
          ('Videos', true),
          ('Music', false),
          ('Online', true),
          ('Videos', true),
          ('Downloads', false),
          ('Online', true),
          ('Home', false),
        ]) {
          await tapTab(tester, tab);
          await tester.pumpAndSettle();
          expect(slot(tester), hidden ? 0 : full, reason: tab);
          expect(miniPlayerHittable(tester), !hidden, reason: tab);
          // The page gets the room the mini player gave up.
          final name = tab.toLowerCase();
          expect(page(tester, name), hidden ? homeHeight + full : homeHeight, reason: tab);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('it folds and unfolds smoothly: the dock never jumps', (tester) async {
        await pumpShell(tester, playing: song);
        final full = slot(tester);
        await tapTab(tester, 'Online');
        final heights = <double>[];
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          heights.add(slot(tester));
        }
        await tester.pumpAndSettle();
        expect(heights.where((h) => h > 0 && h < full), isNotEmpty, reason: 'in between: $heights');
        for (var i = 1; i < heights.length; i++) {
          expect(heights[i], lessThanOrEqualTo(heights[i - 1]), reason: 'it only shrinks: $heights');
        }
        expect(slot(tester), 0);

        await tapTab(tester, 'Music');
        await tester.pump(const Duration(milliseconds: 80));
        final midway = slot(tester);
        expect(midway, inExclusiveRange(0, full));
        await tester.pumpAndSettle();
        expect(slot(tester), full);
      });

      testWidgets('with reduced motion it simply goes and comes back', (tester) async {
        await pumpShell(tester, playing: song, reduceMotion: true);
        final full = slot(tester);
        await tapTab(tester, 'Videos');
        await tester.pump();
        expect(slot(tester), 0);
        await tapTab(tester, 'Home');
        await tester.pump();
        expect(slot(tester), full);
      });

      testWidgets('while folded it is not read out and takes no taps', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpShell(tester, playing: song);
        expect(find.semantics.byLabel('Mini player: Bohemian Rhapsody by Queen'), findsOne);
        await tapTab(tester, 'Online');
        await tester.pumpAndSettle();
        expect(find.semantics.byLabel('Mini player: Bohemian Rhapsody by Queen'), findsNothing);
        expect(find.text('Bohemian Rhapsody').hitTestable(), findsNothing);
        await tapTab(tester, 'Home');
        await tester.pumpAndSettle();
        expect(find.semantics.byLabel('Mini player: Bohemian Rhapsody by Queen'), findsOne);
        handle.dispose();
      });

      testWidgets('a YouTube card in the mini player is hidden on Online and Videos too', (tester) async {
        const yt = ExternalMediaSnapshot(
          id: 'online:dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
          playing: true,
          canSkipNext: true,
        );
        await pumpShell(tester, external: yt);
        await tester.pumpAndSettle();
        expect(find.text('Never Gonna Give You Up').hitTestable(), findsOneWidget);
        for (final tab in ['Online', 'Videos']) {
          await tapTab(tester, tab);
          await tester.pumpAndSettle();
          expect(slot(tester), 0, reason: tab);
          expect(find.text('Never Gonna Give You Up').hitTestable(), findsNothing, reason: tab);
        }
        await tapTab(tester, 'Music');
        await tester.pumpAndSettle();
        expect(find.text('Never Gonna Give You Up').hitTestable(), findsOneWidget);
      });
    });
  });
}

class _FixedExternal extends ExternalMediaNotifier {
  _FixedExternal(this.value);
  final ExternalMediaSnapshot? value;

  @override
  ExternalMediaSnapshot? build() => value;
}

/// No local track: the mini player row is hidden.
/// A music player whose messages a test sends ([messages]).
class _MessagesHandler extends MusicAudioHandler {
  _MessagesHandler(AudioPlayer player) : super(player: player);

  final messages = StreamController<String>.broadcast();

  @override
  Stream<String> get errorEvents => messages.stream;
}

class _NothingPlaying extends PlaybackNotifier {
  @override
  domain.PlaybackState build() => domain.PlaybackState(updatedAt: DateTime(2026));
}
