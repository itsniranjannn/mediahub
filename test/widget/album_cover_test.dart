import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_colors.dart';
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

  Future<void> pump(WidgetTester tester, Widget home, {List<Override> extra = const []}) async {
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
        child: MaterialApp(theme: AppTheme.darkTheme, home: home),
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

  testWidgets('the album header uses the tile\'s song, 16 dp corners and the shared separator', (tester) async {
    mockArtwork();
    await pump(tester, AlbumDetailScreen(album: _group));

    final hero = tester.widget<ArtworkThumbnail>(find.byType(ArtworkThumbnail));
    expect(hero.uri, _coverUri, reason: 'not songs.first (${_songs.first.uri})');
    expect(hero.borderRadius, AppSpacing.lg16);
    expect(hero.placeholderSeed, ArtworkPlaceholder.albumSeed(_album));
    expect(find.text('2 songs · 8 min'), findsOneWidget);

    // No cover: the header keeps the placeholder's palette.
    expect(heroTint(ArtworkTint.surfaceGradient(ArtworkPlaceholder.albumSeed(_album))), findsOneWidget);
  });

  testWidgets('a real cover switches the header and glow to the neutral violet once it loads', (tester) async {
    mockArtwork(withArt: _coverUri);
    await pump(tester, AlbumDetailScreen(album: _group));
    await tester.pump(const Duration(milliseconds: 300));

    expect(heroTint(AppColors.heroGradient), findsOneWidget);
    final glow = find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        w.decoration is BoxDecoration &&
        ((w.decoration! as BoxDecoration).boxShadow?.single.color == AppColors.primaryBase.withValues(alpha: 0.28)));
    expect(glow, findsOneWidget);
  });

  testWidgets('Play is the solid primary button and Shuffle the tonal one, from the theme', (tester) async {
    mockArtwork();
    await pump(tester, AlbumDetailScreen(album: _group));

    Material fill(String label) => tester.widget<Material>(
          find
              .descendant(
                // FilledButton.icon / .tonalIcon are FilledButton subclasses.
                of: find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton)),
                matching: find.byType(Material),
              )
              .first,
        );
    expect(fill('Play').color, AppColors.primary);
    expect(fill('Shuffle').color, const Color(0xFF25253F));
    expect(fill('Shuffle').textStyle?.color, AppColors.primary);
  });
}
