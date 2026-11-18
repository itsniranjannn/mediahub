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
import 'package:mediahub/domain/models/playback_state.dart' as domain;
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

    Future<void> pumpShell(
      WidgetTester tester, {
      List<DownloadEntry> downloads = const [],
      double width = 360,
      double textScale = 1,
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
          ],
          // The phone is in light mode: the dock stays ink.
          child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Rect indicator(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('nav_indicator')));

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
  });
}

/// No local track: the mini player row is hidden.
class _NothingPlaying extends PlaybackNotifier {
  @override
  domain.PlaybackState build() => domain.PlaybackState(updatedAt: DateTime(2026));
}
