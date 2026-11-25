// Settings → You → Your name, and the Home greeting that uses it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/home/greeting_name.dart';
import 'package:mediahub/features/home/home_screen.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mediahub/features/settings/user_name_setting.dart';
import 'package:mediahub/personal/personal_tools_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/app_fonts.dart';
import '../unit/fake_extractor_backend.dart';

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

class _EmptyRepo implements LibraryRepository {
  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) =>
      Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20}) => Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchFavorites({String? searchQuery}) => Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20}) => Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType}) => Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10}) => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _artChannel = MethodChannel('mediahub/media_store');
const _longNepali = 'श्रीकृष्णप्रसाद भट्टराई कोइराला';

void main() {
  setUpAll(() async {
    DiagnosticsService.enableDebounce = false;
    await loadAppFonts();
  });

  setUp(() {
    SettingsStore.instance.remove(UserNameNotifier.prefKey);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_artChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, null);
    ArtworkService.instance.clearCache();
  });

  test('userNameProvider trims, caps at 24 characters, persists and clears', () {
    final a = ProviderContainer();
    addTearDown(a.dispose);
    a.read(userNameProvider.notifier).set('   निरञ्जन   ');
    expect(a.read(userNameProvider), 'निरञ्जन');
    expect(SettingsStore.instance.getStringList(UserNameNotifier.prefKey), ['निरञ्जन']);

    final b = ProviderContainer();
    addTearDown(b.dispose);
    expect(b.read(userNameProvider), 'निरञ्जन');

    b.read(userNameProvider.notifier).set('x' * 40);
    expect(b.read(userNameProvider).length, UserNameNotifier.maxLength);

    b.read(userNameProvider.notifier).clear();
    expect(b.read(userNameProvider), '');
    expect(SettingsStore.instance.getStringList(UserNameNotifier.prefKey), isEmpty);
  });

  testWidgets('Settings dialog saves and clears the name', (tester) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      extractorBackendProvider.overrideWithValue(FakeExtractorBackend()),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(360 * 3, 8000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: SettingsSectionPage(section: SettingsSection.appearance)),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings_user_name')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('user_name_field')), '  Niru  ');
    await tester.tap(find.byKey(const ValueKey('user_name_save')));
    await tester.pumpAndSettle();
    expect(container.read(userNameProvider), 'Niru');
    expect(find.text('Niru'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings_user_name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('user_name_clear')));
    await tester.pumpAndSettle();
    expect(container.read(userNameProvider), '');
    expect(find.textContaining('Not set'), findsOneWidget);
  });

  Future<void> pumpHome(WidgetTester tester, {String name = '', ThemeData? theme, bool reduceMotion = false}) async {
    if (name.isNotEmpty) SettingsStore.instance.setStringList(UserNameNotifier.prefKey, [name]);
    tester.view.physicalSize = const Size(360 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(_EmptyRepo()),
        currentMediaItemProvider.overrideWith((ref) => null),
        isPlayingProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    ));
  }

  testWidgets('Home keeps the plain greeting without a name', (tester) async {
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('नमस्ते'), findsOneWidget);
    expect(find.byType(GreetingName), findsNothing);
  });

  final themes = {'dark': AppTheme.darkTheme, 'light': AppTheme.lightTheme};
  for (final entry in themes.entries) {
    testWidgets('Home shows a long Devanagari name without overflow (${entry.key}, 360 dp, 1.3x)', (tester) async {
      await pumpHome(tester, name: _longNepali, theme: entry.value);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      expect(find.text(GreetingName.namaste), findsOneWidget);
      expect(find.text(_longNepali), findsOneWidget);
      final text = tester.widget<Text>(find.byKey(const ValueKey('greeting_name')));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.getRect(find.byKey(const ValueKey('greeting_name'))).right, lessThanOrEqualTo(360));
    });
  }

  testWidgets('reduced motion draws the name static at once', (tester) async {
    await pumpHome(tester, name: 'Niru', reduceMotion: true);
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.byKey(const ValueKey('greeting_name')), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1);
    final rotate = tester.widget<Transform>(
      find.ancestor(of: find.byKey(const ValueKey('greeting_wave')), matching: find.byType(Transform)).first,
    );
    expect(rotate.transform, Matrix4.identity());
  });
}
