// Settings → Privacy & permissions on iPhone (iOS parity P3, task 3): the
// iPhone app reads nothing else on the phone, so "Your music and videos"
// says it only plays what you download in MediaHub, and App permissions
// points at iPhone Settings (and says so when it cannot open them).
// Android keeps its words.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/settings/settings_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

class _MockPermissions extends Mock implements MediaPermissionService {}

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

const _androidMedia = 'To find and play them. MediaHub never uploads them.';
const _iphoneMedia = 'Only the ones you download in MediaHub. MediaHub never uploads them.';
const _androidPermissions = 'See or change what MediaHub may use, in your phone\'s settings.';
const _iphonePermissions = 'See or change what MediaHub may use, in iPhone Settings.';
const _androidCannotOpen = "Could not open your phone's settings.";
const _iphoneCannotOpen = 'Could not open iPhone Settings.';

void main() {
  setUpAll(() => DiagnosticsService.enableDebounce = false);
  tearDown(PlatformInfo.resetForTests);

  Future<void> pump(WidgetTester tester, {MediaPermissionService? permissions}) async {
    final handler = _handler();
    addTearDown(handler.dispose);
    final container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      if (permissions != null) mediaPermissionServiceProvider.overrideWithValue(permissions),
    ]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 11000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
  }

  testWidgets('iPhone: only what you download in MediaHub, and iPhone Settings', (tester) async {
    PlatformInfo.debugIsIOS = true;
    await pump(tester);
    expect(find.text('Your music and videos'), findsOneWidget);
    expect(find.text(_iphoneMedia), findsOneWidget);
    expect(find.text(_androidMedia), findsNothing, reason: 'the iPhone app does not look for them on the phone');
    expect(find.text(_iphonePermissions), findsOneWidget);
    expect(find.text(_androidPermissions), findsNothing);
  });

  testWidgets('Android keeps its words', (tester) async {
    PlatformInfo.debugIsAndroid = true;
    await pump(tester);
    expect(find.text(_androidMedia), findsOneWidget);
    expect(find.text(_androidPermissions), findsOneWidget);
    expect(find.text(_iphoneMedia), findsNothing);
    expect(find.text(_iphonePermissions), findsNothing);
  });

  for (final ios in [true, false]) {
    testWidgets('App permissions that cannot open says so (${ios ? 'iPhone' : 'Android'})', (tester) async {
      if (ios) {
        PlatformInfo.debugIsIOS = true;
      } else {
        PlatformInfo.debugIsAndroid = true;
      }
      final permissions = _MockPermissions();
      when(() => permissions.openSettings()).thenAnswer((_) async => false);
      await pump(tester, permissions: permissions);
      // Android has more rows above it: bring the row on screen first.
      await tester.ensureVisible(find.text('App permissions'));
      await tester.pump();
      await tester.tap(find.text('App permissions'));
      await tester.pump();
      verify(() => permissions.openSettings()).called(1);
      expect(find.text(_iphoneCannotOpen), ios ? findsOneWidget : findsNothing);
      expect(find.text(_androidCannotOpen), ios ? findsNothing : findsOneWidget);
    });
  }
}
