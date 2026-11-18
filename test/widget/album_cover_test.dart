import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_spacing.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/core/widgets/artwork_thumbnail.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';
import 'package:mocktail/mocktail.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

class _MockMediaPermissionService extends Mock implements MediaPermissionService {}

const _channel = MethodChannel('mediahub/media_store');
const _album = 'Songs of the Hills';

MediaItem _song(String id, String title) => MediaItem(
      id: id,
      uri: 'content://media/external/audio/media/$id',
      mediaType: MediaType.audio,
      title: title,
      artist: 'Himal Sessions',
      album: _album,
      durationMs: 240000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

// Sorted by title, so the cover song (smallest uri) is not the first row.
final _songs = [_song('20', 'Annapurna Dawn'), _song('10', 'Valley Rain')];
final _coverUri = _songs[1].uri;
final _group = AlbumGroup(
  album: _album,
  artist: 'Himal Sessions',
  songCount: 2,
  totalDurationMs: 480000,
  coverUri: _coverUri,
);

void main() {
  late _MockLibraryRepository repo;

  setUpAll(() => registerFallbackValue(MediaSortOption.title));

  setUp(() {
    ArtworkService.instance.clearCache();
    repo = _MockLibraryRepository();
    when(() => repo.scanDeviceMedia()).thenAnswer((_) async {});
    when(() => repo.watchAlbumSongs(_album)).thenAnswer((_) => Stream.value(_songs));
    when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value([_group]));
    when(() => repo.watchArtists(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchPlaylists()).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchFavorites(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value([]));
    when(() => repo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => Stream.value(_songs));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    ArtworkService.instance.clearCache();
  });

  /// The device has a cover only for [withArt] (or for nothing).
  void mockArtwork({String? withArt}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method != 'getArtwork') return null;
      final uri = (call.arguments as Map)['uri'];
      return uri == withArt ? Uint8List.fromList([1, 2, 3]).toList() : null;
    });
  }

  Future<void> pump(WidgetTester tester, Widget home, {List<Override> extra = const [], ThemeData? theme}) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          currentMediaItemProvider.overrideWith((ref) => null),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
          ...extra,
        ],
        child: MaterialApp(theme: theme ?? AppTheme.darkTheme, home: home),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder heroTint(Gradient gradient) => find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient == gradient,
      );

  testWidgets('the album tile shows the same song cover as the album page', (tester) async {
    mockArtwork();
    final permissions = _MockMediaPermissionService();
    when(() => permissions.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => permissions.checkVideoPermission()).thenAnswer((_) async => MediaPermissionState.granted);

    await pump(tester, const MusicScreen(), extra: [mediaPermissionServiceProvider.overrideWithValue(permissions)]);
    await tester.tap(find.text('Albums'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final tile = tester.widget<ArtworkThumbnail>(find.byWidgetPredicate(
      (w) => w is ArtworkThumbnail && w.placeholderSeed == ArtworkPlaceholder.albumSeed(_album),
    ));
    expect(tile.uri, _coverUri);
    expect(tile.placeholderIcon, Icons.album_rounded);
    expect(find.text(_album), findsOneWidget);
  });

  testWidgets('the album header uses the tile\'s song, the thumbnail radius and the shared separator', (tester) async {
    mockArtwork();
    await pump(tester, AlbumDetailScreen(album: _group));

    final hero = tester.widget<ArtworkThumbnail>(find.byType(ArtworkThumbnail));
    expect(hero.uri, _coverUri, reason: 'not songs.first (${_songs.first.uri})');
    expect(hero.borderRadius, AppSpacing.radiusThumb);
    expect(hero.placeholderSeed, ArtworkPlaceholder.albumSeed(_album));
    expect(find.text('2 songs · 8 min'), findsOneWidget);

    // No cover: the header keeps the placeholder's palette.
    expect(heroTint(ArtworkTint.surfaceGradient(ArtworkPlaceholder.albumSeed(_album))), findsOneWidget);
  });

  /// The hard print offset under the hero cover (DESIGN.md 7.1).
  Finder printOffset(Color color) => find.byWidgetPredicate((w) {
        if (w is! DecoratedBox || w.decoration is! BoxDecoration) return false;
        final shadows = (w.decoration as BoxDecoration).boxShadow;
        return shadows != null &&
            shadows.length == 1 &&
            shadows.single.offset == const Offset(6, 6) &&
            shadows.single.blurRadius == 0 &&
            shadows.single.color == color;
      });

  testWidgets('a real cover switches the header to the neutral hero tint once it loads', (tester) async {
    mockArtwork(withArt: _coverUri);
    await pump(tester, AlbumDetailScreen(album: _group));
    await tester.pump(const Duration(milliseconds: 300));

    expect(heroTint(AppPalette.dark.heroGradient), findsOneWidget);
    // No soft glow: the cover sits on the hard Volt print offset.
    expect(printOffset(AppPalette.dark.printShadow), findsOneWidget);
  });

  testWidgets('on paper the header is the lavender wash and the print offset is ink', (tester) async {
    mockArtwork(withArt: _coverUri);
    await pump(tester, AlbumDetailScreen(album: _group), theme: AppTheme.lightTheme);
    await tester.pump(const Duration(milliseconds: 300));

    expect(heroTint(AppPalette.light.heroGradient), findsOneWidget);
    expect(printOffset(AppPalette.light.printShadow), findsOneWidget);
    expect(AppPalette.light.printShadow, const Color(0xFF180A2E));
    final kicker = tester.widget<Text>(find.text('ALBUM'));
    expect(kicker.style?.color, AppPalette.light.primary);
  });

  testWidgets('"Play all" is the Volt button and plays the album; Shuffle is the tonal one', (tester) async {
    mockArtwork();
    await pump(tester, AlbumDetailScreen(album: _group));

    final play = tester.widget<VoltButton>(find.widgetWithText(VoltButton, 'Play all'));
    expect(play.onPressed, isNotNull);
    expect(play.icon, Icons.play_arrow_rounded);

    final shuffle = tester.widget<Material>(
      find
          .descendant(
            of: find.ancestor(of: find.text('Shuffle'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
            matching: find.byType(Material),
          )
          .first,
    );
    // Bijuli's tonal pair (DESIGN.md 2.3): deep violet fill, pale Volt label.
    expect(shuffle.color, AppPalette.dark.secondaryContainer);
    expect(shuffle.textStyle?.color, AppPalette.dark.onSecondaryContainer);
  });

  testWidgets('album songs show track numbers, not covers, and nothing overflows at 1.3x on 320 dp', (tester) async {
    mockArtwork();
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, AlbumDetailScreen(album: _group));
    tester.view.physicalSize = const Size(320 * 3, 800 * 3);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    // Only the hero cover; the rows carry numbers instead.
    expect(find.byType(ArtworkThumbnail), findsOneWidget);
  });
}
