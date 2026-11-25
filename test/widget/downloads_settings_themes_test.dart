// Downloads, Settings (with Appearance), Diagnostics and the quality sheet
// in both Bijuli themes (docs/DESIGN.md 7.10, 7.14, 8.2): every layout holds
// at textScaler 1.3 on 320 and 360 dp phones with the real fonts, the
// Downloads rows show each state as an icon and a word, and Settings →
// Appearance saves System / Dark / Light.
//
// Set PREVIEW_OUT=<dir> to also write a PNG of every layout scene there.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/app/app.dart';
import 'package:mediahub/app/router.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/app/theme/ink_theme.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/domain/models/download_progress.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/settings/diagnostics_screen.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/features/settings/theme_mode_setting.dart';
import 'package:mediahub/personal/extractor_backend.dart';
import 'package:mediahub/personal/format_options.dart';
import 'package:mediahub/personal/format_selection_sheet.dart';

import '../helpers/app_fonts.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

MusicAudioHandler _handler() {
  final p = _MockAudioPlayer();
  when(() => p.playbackEventStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playerStateStream).thenAnswer((_) => const Stream.empty());
  when(() => p.currentIndexStream).thenAnswer((_) => const Stream.empty());
  when(() => p.positionStream).thenAnswer((_) => const Stream.empty());
  when(() => p.durationStream).thenAnswer((_) => const Stream.empty());
  when(() => p.dispose()).thenAnswer((_) async {});
  return MusicAudioHandler(player: p);
}

/// The running download's live speed and time left.
class _FixedProgress extends DownloadProgressMapNotifier {
  @override
  Map<String, DownloadProgressUpdate> build() => const {
        'run': DownloadProgressUpdate(
          id: 'run',
          receivedBytes: 412 * 1024 * 1024,
          totalBytes: 664 * 1024 * 1024,
          speedBytesPerSec: 2.4 * 1024 * 1024,
          eta: Duration(minutes: 1, seconds: 45),
        ),
      };
}

const _mb = 1024 * 1024;

DownloadEntry _entry(
  String id,
  DownloadTaskState state, {
  required String title,
  String kind = 'video',
  int received = 0,
  int? total,
  String? quality,
  String? errorCode,
}) {
  final now = DateTime(2026, 11, 17, 12);
  return DownloadEntry(
    id: id,
    url: 'https://example.com/$id',
    host: 'www.youtube.com',
    displayName: title,
    fileName: '$title.${kind == 'audio' ? 'm4a' : 'mp4'}',
    state: state.name,
    receivedBytes: received,
    totalBytes: total,
    supportsRange: true,
    errorCode: errorCode,
    createdAt: now,
    updatedAt: now,
    kind: kind,
    engine: 'direct',
    qualityLabel: quality,
  );
}

/// One row in every state the screen draws, with Nepali and file-style titles.
final _rows = [
  _entry('run', DownloadTaskState.downloading,
      title: 'Pokhara_lake_drone_4K', received: 412 * _mb, total: 664 * _mb, quality: '1080p'),
  _entry('prep', DownloadTaskState.finalizing, title: 'झिलिमिली साँझ - Official Video', total: 80 * _mb),
  _entry('wait', DownloadTaskState.queued, title: 'रेशम फिरिरी', kind: 'audio', total: 4 * _mb, quality: 'Audio 128 kbps'),
  _entry('hold', DownloadTaskState.paused, title: 'क्षितिज पारि', received: 30 * _mb, total: 120 * _mb),
  _entry('done', DownloadTaskState.completed,
      title: 'Audit_Long_Tone_5min', kind: 'audio', received: 5 * _mb, total: 5 * _mb),
  _entry('fail', DownloadTaskState.failed, title: 'Dashain at home, part 2', errorCode: 'x_network_error'),
];

final _shotKey = GlobalKey();
final _outDir = Platform.environment['PREVIEW_OUT'];

/// Writes the scene to PREVIEW_OUT when it is set.
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = _outDir;
  if (dir == null || dir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// The Material icon font, only needed for readable PNGs.
Future<void> _loadIcons() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  final font = File('${Platform.environment['FLUTTER_ROOT'] ?? dir.path}'
      '/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (!font.existsSync()) return;
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(font.readAsBytesSync().buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    DiagnosticsService.enableDebounce = false;
    await loadAppFonts();
    final out = _outDir;
    if (out != null && out.isNotEmpty) {
      Directory(out).createSync(recursive: true);
      await _loadIcons();
    }
  });

  void phone(WidgetTester tester, double width, double scale) {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget app(AppPalette palette, Widget home) => RepaintBoundary(
        key: _shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(palette),
          home: home,
        ),
      );

  for (final palette in [AppPalette.dark, AppPalette.light]) {
    final theme = palette.isDark ? 'dark' : 'light';

    for (final (width, scale) in [(320.0, 1.3), (360.0, 1.3), (360.0, 1.0)]) {
      final size = '${width.toInt()}dp x$scale';

      testWidgets('$theme $size: Downloads holds with a row in every state', (tester) async {
        phone(tester, width, scale);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        // Tall enough to lay out every row (the list is lazy).
        tester.view.physicalSize = Size(width * 3, 2400 * 3);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            downloadsStreamProvider.overrideWith((ref) => Stream.value(_rows)),
            downloadProgressMapProvider.overrideWith(_FixedProgress.new),
            storageInfoProvider.overrideWith(
              (ref) => Future.value(const StorageInfo(usedBytes: 690 * _mb, freeBytes: 1288490189)),
            ),
          ],
          child: app(palette, const DownloadsScreen()),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await _shot(tester, 'downloads_${theme}_${width.toInt()}_${(scale * 10).toInt()}');

        // The masthead summary and each state as an icon and a word.
        expect(find.text('Downloads'), findsOneWidget);
        expect(find.text('2 ACTIVE · 1.2 GB FREE'), findsOneWidget);
        for (final word in ['Queued', 'Paused', 'Saved', 'Failed']) {
          expect(find.text(word), findsOneWidget, reason: word);
        }
        expect(find.text('62%'), findsOneWidget, reason: 'the running download');
        expect(find.textContaining('MB/s'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget, reason: 'Failed has a Retry button');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('$theme $size: Settings holds, Appearance included', (tester) async {
        phone(tester, width, scale);
        tester.view.physicalSize = Size(width * 3, 3200 * 3);
        final handler = _handler();
        addTearDown(handler.dispose);
        await tester.pumpWidget(ProviderScope(
          overrides: [audioHandlerProvider.overrideWithValue(handler)],
          child: app(palette, const SettingsScreen()),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _shot(tester, 'settings_${theme}_${width.toInt()}_${(scale * 10).toInt()}');
      });

      testWidgets('$theme $size: Diagnostics holds', (tester) async {
        phone(tester, width, scale);
        await DiagnosticsService.instance.clear();
        DiagnosticsService.instance.logEvent('service_start');
        DiagnosticsService.instance.logEvent('player_error', {'error': 'Source error', 'code': 403});
        DiagnosticsService.instance.logEvent('play', {'caller': 'in_app', 'title': 'रेशम फिरिरी'});
        await tester.pumpWidget(app(palette, const DiagnosticsScreen()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _shot(tester, 'diagnostics_${theme}_${width.toInt()}_${(scale * 10).toInt()}');
      });

      testWidgets('$theme $size: the quality sheet holds', (tester) async {
        phone(tester, width, scale);
        await tester.pumpWidget(app(
          palette,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => FormatSelectionSheet(
                      metadata: const ExtractorMetadata(
                        id: 'abc',
                        title: 'Audit_Long_Tone_5min · झिलिमिली साँझ',
                        uploader: 'Himal Sessions',
                        durationSec: 301,
                        thumbnailUrl: '',
                        formats: [],
                      ),
                      choices: const [
                        FormatChoice(
                          id: 'v',
                          label: '1080p',
                          subtitle: 'MP4 · 85.0 MB',
                          isAudio: false,
                          selector: 'v',
                          qualityLabel: '1080p',
                        ),
                        FormatChoice(
                          id: 'a',
                          label: 'Audio only (M4A, 128 kbps)',
                          subtitle: 'M4A · size unknown',
                          isAudio: true,
                          selector: 'a',
                          qualityLabel: 'Audio 128 kbps',
                        ),
                      ],
                      footnote: 'Only the qualities YouTube serves directly are listed.',
                      onSelect: (_) {},
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('VIDEO WITH SOUND'), findsOneWidget);
        expect(find.text('MP4 · 85.0 MB'), findsOneWidget, reason: 'one line, the size in DM Mono');
        await _shot(tester, 'quality_sheet_${theme}_${width.toInt()}_${(scale * 10).toInt()}');
      });
    }
  }

  group('Settings → Appearance', () {
    setUp(() => SettingsStore.instance.setStringList(AppearanceSettingNotifier.prefKey, const []));

    Future<ProviderContainer> pump(WidgetTester tester) async {
      final handler = _handler();
      addTearDown(handler.dispose);
      final container = ProviderContainer(overrides: [audioHandlerProvider.overrideWithValue(handler)]);
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1080, 11000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pump();
      return container;
    }

    RadioListTile<AppearanceChoice> option(WidgetTester tester, AppearanceChoice choice) =>
        tester.widget<RadioListTile<AppearanceChoice>>(find.byKey(ValueKey('appearance_${choice.name}')));

    RadioGroup<AppearanceChoice> group(WidgetTester tester) =>
        tester.widget<RadioGroup<AppearanceChoice>>(find.byType(RadioGroup<AppearanceChoice>));

    testWidgets('follows the phone by default; four choices, Bijuli Classic last', (tester) async {
      final c = await pump(tester);
      expect(c.read(appearanceSettingProvider), AppearanceChoice.system);
      expect(c.read(themeModeSettingProvider), ThemeMode.system);
      expect(find.text('Appearance'), findsOneWidget);
      for (final label in ['System', 'Dark', 'Light', 'Bijuli Classic']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('The original lime-on-violet look. Always dark.'), findsOneWidget);
      expect(find.byKey(const ValueKey('appearance_classic')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('appearance_classic')), matching: find.byIcon(Icons.bolt_outlined)),
          findsOneWidget);
      expect(group(tester).groupValue, AppearanceChoice.system);
      expect(option(tester, AppearanceChoice.system).value, AppearanceChoice.system);
    });

    testWidgets('a choice applies at once and is saved', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(c.read(themeModeSettingProvider), ThemeMode.light);
      expect(SettingsStore.instance.getStringList(AppearanceSettingNotifier.prefKey), ['light']);
      expect(group(tester).groupValue, AppearanceChoice.light);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(c.read(themeModeSettingProvider), ThemeMode.dark);
      expect(SettingsStore.instance.getStringList(AppearanceSettingNotifier.prefKey), ['dark']);

      await tester.tap(find.text('Bijuli Classic'));
      await tester.pump();
      expect(c.read(appearanceSettingProvider), AppearanceChoice.classic);
      expect(c.read(themeModeSettingProvider), ThemeMode.dark, reason: 'Bijuli Classic is always dark');
      expect(SettingsStore.instance.getStringList(AppearanceSettingNotifier.prefKey), ['classic']);
      expect(group(tester).groupValue, AppearanceChoice.classic);
    });

    testWidgets('MediaHubApp hands the choice to MaterialApp.themeMode, and it applies at once', (tester) async {
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const Scaffold(body: Text('page')))]);
      addTearDown(router.dispose);
      final c = ProviderContainer(overrides: [routerProvider.overrideWithValue(router)]);
      addTearDown(c.dispose);
      // The phone is dark.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MediaHubApp()));
      await tester.pumpAndSettle();

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      Brightness shown() => Theme.of(tester.element(find.text('page'))).brightness;
      expect(app().themeMode, ThemeMode.system);
      expect(app().theme, same(AppTheme.lightTheme));
      expect(app().darkTheme, same(AppTheme.darkTheme));
      expect(shown(), Brightness.dark, reason: 'System follows the dark phone');

      c.read(appearanceSettingProvider.notifier).set(AppearanceChoice.light);
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.light);
      expect(shown(), Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      c.read(appearanceSettingProvider.notifier).set(AppearanceChoice.dark);
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      expect(shown(), Brightness.dark, reason: 'Dark holds on a light phone');

      c.read(appearanceSettingProvider.notifier).set(AppearanceChoice.system);
      await tester.pumpAndSettle();
      expect(shown(), Brightness.light, reason: 'System follows the phone again');
    });

    testWidgets('Bijuli Classic: darkTheme is the classic theme, always dark, and InkTheme follows', (tester) async {
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const Scaffold(body: Text('page')))]);
      addTearDown(router.dispose);
      final c = ProviderContainer(overrides: [routerProvider.overrideWithValue(router)]);
      addTearDown(c.dispose);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MediaHubApp()));
      await tester.pumpAndSettle();

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      BuildContext page() => tester.element(find.text('page'));
      expect(InkTheme.of(page()), same(AppTheme.darkTheme));

      c.read(appearanceSettingProvider.notifier).set(AppearanceChoice.classic);
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      expect(app().darkTheme, same(AppTheme.classicTheme));
      expect(Theme.of(page()).extension<AppPalette>(), same(AppPalette.classic), reason: 'dark on a light phone');
      expect(InkTheme.of(page()), same(AppTheme.classicTheme));
      expect(InkTheme.paletteOf(page()), same(AppPalette.classic));

      c.read(appearanceSettingProvider.notifier).set(AppearanceChoice.light);
      await tester.pumpAndSettle();
      expect(app().darkTheme, same(AppTheme.darkTheme));
      expect(InkTheme.of(page()), same(AppTheme.darkTheme), reason: 'the dock is Sindur dark again');
      expect(Theme.of(page()).extension<AppPalette>(), same(AppPalette.light));
    });

    testWidgets('a saved choice is read back; anything unknown means System', (tester) async {
      await SettingsStore.instance.setStringList(AppearanceSettingNotifier.prefKey, ['dark']);
      final c = await pump(tester);
      expect(c.read(themeModeSettingProvider), ThemeMode.dark);
      expect(AppearanceSettingNotifier.decode(['sepia']), AppearanceChoice.system);
      expect(AppearanceSettingNotifier.decode(const []), AppearanceChoice.system);
      expect(AppearanceSettingNotifier.decode(['system']), AppearanceChoice.system);
      expect(AppearanceSettingNotifier.decode(['light']), AppearanceChoice.light);
      expect(AppearanceSettingNotifier.decode(['classic']), AppearanceChoice.classic);
    });

    testWidgets('a saved Bijuli Classic choice persists across a restart', (tester) async {
      await SettingsStore.instance.setStringList(AppearanceSettingNotifier.prefKey, ['classic']);
      final c = await pump(tester);
      expect(c.read(appearanceSettingProvider), AppearanceChoice.classic);
      expect(c.read(themeModeSettingProvider), ThemeMode.dark);
      expect(group(tester).groupValue, AppearanceChoice.classic);
    });
  });
}
