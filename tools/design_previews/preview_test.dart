// Preview renders for design reviews (not part of the test suite).
// Besides the screens: a 'components' sheet (type roles, Volt widgets,
// chips, switches, inputs, badges, the Ink Dock), a dialog with a snackbar,
// and the Online tab's toolbar and menu over a stand-in WebView. Several
// scenes also render at 320 dp and at 1.3x text.
// The bundled Bijuli fonts + MaterialIcons, 360x800 dp at 3x, every scene in
// the ink (dark) and the paper (light) theme: <scene>_dark.png and
// <scene>_light.png (PREVIEW_THEMES=dark or =light renders one). Some titles
// are Nepali and one is a file-style name, to check Devanagari and
// underscore wrapping. Most scenes have no artwork
// so every cover shows its placeholder; the *_art and *_bright scenes give
// some items a real cover (generated PNGs: a file for artworkPath, or bytes
// from a mocked device-art channel) to check tints and contrast over art.
//
// Run from the repo root:
//   flutter test tools/design_previews/preview_test.dart --timeout 300s
// PNGs land in build/design_previews/ (or $PREVIEW_OUT).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/app/theme/app_typography.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/models/video_progress.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/features/home/home_screen.dart';
import 'package:mediahub/features/library/detail_screens.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/mini_player.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/music_screen.dart';
import 'package:mediahub/features/music_player/now_playing_sheet.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/music_player/queue_sheet.dart';
import 'package:mediahub/features/online/online_media_session.dart';
import 'package:mediahub/features/online/online_screen.dart';
import 'package:mediahub/features/online/online_settings.dart';
import 'package:mediahub/features/online/online_web_view.dart';
import 'package:mediahub/features/video_player/video_player_notifier.dart';
import 'package:mediahub/features/video_player/videos_screen.dart';
import 'package:mediahub/shared/widgets/artwork_placeholder.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';
import 'package:mocktail/mocktail.dart';

import '../../test/helpers/app_fonts.dart';
import '../../test/widget/online_fakes.dart';

final repoRoot = Directory.current.path.replaceAll(r'\', '/');
final outDir = Platform.environment['PREVIEW_OUT'] ?? '$repoRoot/build/design_previews';

/// The Flutter SDK folder, for the Material icon font.
String flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_tester lives in <sdk>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
}
final shotKey = GlobalKey();

/// The themes every scene renders in.
final previewThemes = switch (Platform.environment['PREVIEW_THEMES']) {
  'dark' => const ['dark'],
  'light' => const ['light'],
  _ => const ['dark', 'light'],
};

/// The theme of the scene being rendered ('dark' or 'light').
var previewTheme = 'dark';

ThemeData get previewThemeData => previewTheme == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;

class MockRepo extends Mock implements LibraryRepository {}

class MockPerm extends Mock implements MediaPermissionService {}

class MockAudioPlayer extends Mock implements AudioPlayer {}

class FakeAudioSource extends Fake implements AudioSource {}

class FakePlaybackState extends Fake implements domain.PlaybackState {}

class MockPlaybackRepository extends Mock implements PlaybackRepository {}

class FakePlayback extends PlaybackNotifier {
  final domain.PlaybackState s;
  FakePlayback(this.s);
  @override
  domain.PlaybackState build() => s;
}

class FakeVideoNotifier extends VideoLibraryNotifier {
  final LibraryState initial;
  FakeVideoNotifier(this.initial);
  @override
  LibraryState build() => initial;
}

class HomeRepo implements LibraryRepository {
  final List<MediaItem> songs;
  final List<MediaItem> videos;
  HomeRepo(this.songs, this.videos);

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) =>
      Stream.value(mediaType == MediaType.audio ? songs : videos);
  @override
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20}) => Stream.value(songs.take(5).toList());
  @override
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20}) => Stream.value(songs.reversed.take(3).toList());
  @override
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType}) =>
      Stream.value(songs.skip(2).take(4).toList());
  @override
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10}) => Stream.value(videos);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MusicAudioHandler makeHandler() {
  final p = MockAudioPlayer();
  when(() => p.playbackEventStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playerStateStream).thenAnswer((_) => const Stream.empty());
  when(() => p.currentIndexStream).thenAnswer((_) => const Stream.empty());
  when(() => p.positionStream).thenAnswer((_) => const Stream.empty());
  when(() => p.durationStream).thenAnswer((_) => const Stream.empty());
  when(() => p.playing).thenReturn(false);
  when(() => p.processingState).thenReturn(ProcessingState.ready);
  when(() => p.position).thenReturn(Duration.zero);
  when(() => p.bufferedPosition).thenReturn(Duration.zero);
  when(() => p.speed).thenReturn(1.0);
  when(() => p.duration).thenReturn(null);
  when(() => p.currentIndex).thenReturn(null);
  when(() => p.shuffleModeEnabled).thenReturn(false);
  when(() => p.hasNext).thenReturn(false);
  when(() => p.hasPrevious).thenReturn(false);
  when(() => p.setShuffleModeEnabled(any())).thenAnswer((_) async {});
  when(() => p.setLoopMode(any())).thenAnswer((_) async {});
  when(() => p.dispose()).thenAnswer((_) async {});
  return MusicAudioHandler(player: p);
}

Future<void> loadFonts() async {
  // Every family of pubspec.yaml's fonts block (Unbounded, AnekWide,
  // AtkinsonNext, Mukta, DMMono).
  await loadAppFonts();
  final icons = FontLoader('MaterialIcons');
  final b = File('${flutterRoot()}/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
      .readAsBytesSync();
  icons.addFont(Future.value(ByteData.view(b.buffer)));
  await icons.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/${name}_$previewTheme.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

// ---------------------------------------------------------------------------
// Generated covers

/// A mostly white sleeve (paper white, a pale sun, light grey type bars):
/// the worst case for light text drawn near a blurred copy of the cover.
Future<Uint8List> brightCoverPng() => _coverPng((canvas, s) {
      canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFBFAF6));
      canvas.drawCircle(
        Offset(s.width * 0.5, s.height * 0.42),
        s.width * 0.2,
        Paint()..color = const Color(0xFFFFEDB8),
      );
      final bar = Paint()..color = const Color(0xFFE4E2DC);
      canvas
        ..drawRect(Rect.fromLTWH(s.width * 0.18, s.height * 0.74, s.width * 0.64, s.height * 0.035), bar)
        ..drawRect(Rect.fromLTWH(s.width * 0.3, s.height * 0.8, s.width * 0.4, s.height * 0.025), bar);
    });

/// A saturated warm cover (red field, orange disc, dark lower band): a
/// typical embedded album cover whose colour has nothing to do with the
/// item's hash palette.
Future<Uint8List> warmCoverPng() => _coverPng((canvas, s) {
      final rect = Offset.zero & s;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD8452E), Color(0xFF8E1B2A)],
          ).createShader(rect),
      );
      canvas.drawCircle(
        Offset(s.width * 0.62, s.height * 0.38),
        s.width * 0.22,
        Paint()..color = const Color(0xFFFFA23A),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, s.height * 0.72, s.width, s.height * 0.28),
        Paint()..color = const Color(0xFF2A0E16),
      );
    });

Future<Uint8List> _coverPng(void Function(Canvas canvas, Size size) paint) async {
  const side = 512;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas, const Size(512, 512));
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

late Uint8List brightCover;
late Uint8List warmCover;
late String brightCoverPath;

const _artChannel = MethodChannel('mediahub/media_store');

/// The device has embedded art for the uris in [art] (any lookup size).
void mockDeviceArt(Map<String, Uint8List> art) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, (call) async {
    if (call.method != 'getArtwork') return null;
    final bytes = art[(call.arguments as Map)['uri']];
    return bytes?.toList();
  });
}

void clearDeviceArt() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, null);
  ArtworkService.instance.clearCache();
}

// ---------------------------------------------------------------------------
// Data

// Nepali titles (docs/DESIGN.md 10.6) and a file-style name sit among Latin
// ones: Anek / Mukta must draw every matra and conjunct without clipping.
const _songData = [
  ('रेशम फिरिरी (Folk Medley)', 'Himal Sessions', 'Songs of the Hills', 245000),
  ('Sunrise Over Phewa Lake', 'Bipana Gurung', 'Pokhara Mornings', 213000),
  ('Midnight Drive - Extended Night Mix with Strings and Field Recordings', 'Neon Atlas Orchestra', 'After Hours', 512000),
  ('झिलिमिली साँझ', 'परिवारको रेकर्डिङ', 'Home Tapes', 158000),
  ('Audit_Long_Tone_5min', 'Field Notes', 'Weather', 301000),
  ('Kathmandu Morning', 'Sajan & Friends', 'Valley Songs', 187000),
  ('The Long Way Home Through the Hills of Ilam, Pt. 2', 'The Ilam Collective feat. Riya Tamang', 'Tea Garden Stories', 389000),
  ('क्षितिज पारि', 'Kite Club', 'Festival', 176000),
];

final songs = [
  for (var i = 0; i < _songData.length; i++)
    MediaItem(
      id: 'song_$i',
      uri: 'content://media/external/audio/media/${1040 + i * 7}',
      mediaType: MediaType.audio,
      title: _songData[i].$1,
      artist: _songData[i].$2,
      album: _songData[i].$3,
      durationMs: _songData[i].$4,
      sizeBytes: 6000000,
      dateAdded: DateTime(2026, 10, 1 + i),
      source: i == 1 || i == 5 ? 'download' : 'device',
      isFavorite: i == 0 || i == 3,
    ),
];

const _videoData = [
  ('Grandma\'s 80th birthday - full party.mp4', 3723000, 1920, 1080),
  ('Trek to Poon Hill sunrise (drone).mp4', 742000, 3840, 2160),
  ('भाइटीका २०८२ - Bhai Tika.mp4', 1265000, 1280, 720),
  ('School concert - Riya singing the folk song solo with the choir.mp4', 418000, 1920, 1080),
  ('Puppy first bath.mp4', 95000, 1080, 1920),
];

final videos = [
  for (var i = 0; i < _videoData.length; i++)
    MediaItem(
      id: 'video_$i',
      uri: 'content://media/external/video/media/${2210 + i * 5}',
      mediaType: MediaType.video,
      title: _videoData[i].$1,
      durationMs: _videoData[i].$2,
      sizeBytes: 250000000 + i * 91000000,
      width: _videoData[i].$3,
      height: _videoData[i].$4,
      dateAdded: DateTime.now().subtract(Duration(days: i * 3)),
      source: i == 2 ? 'download' : 'device',
    ),
];

domain.PlaybackState playing(int index, {bool isPlaying = true}) => playingFrom(songs, index, isPlaying: isPlaying);

domain.PlaybackState playingFrom(List<MediaItem> queue, int index, {bool isPlaying = true}) => domain.PlaybackState(
      currentItemId: queue[index].id,
      queue: queue,
      queueIndex: index,
      position: const Duration(seconds: 74),
      duration: Duration(milliseconds: queue[index].durationMs),
      isPlaying: isPlaying,
      updatedAt: DateTime(2026),
    );

/// Index of the first song whose placeholder palette is one of [wanted]
/// (in order of preference) and differs from song [other]'s.
int songWithPalette(List<int> wanted, {required int other}) {
  final avoid = ArtworkPlaceholder.paletteIndexFor(songs[other].uri);
  for (final p in wanted) {
    if (p == avoid) continue;
    final i = songs.indexWhere((s) => ArtworkPlaceholder.paletteIndexFor(s.uri) == p);
    if (i >= 0) return i;
  }
  return songs.indexWhere((s) => ArtworkPlaceholder.paletteIndexFor(s.uri) != avoid);
}

// ---------------------------------------------------------------------------
// Components sheet (docs/DESIGN.md 6 and 7): every type role, the Volt
// widgets, buttons, chips, switches, inputs, badges and an empty state.

Widget componentsSheet(BuildContext context) {
  final p = context.palette;
  final t = AppTypography.of(p);
  Widget gap([double h = 12]) => SizedBox(height: h);
  Widget role(String name, TextStyle style, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 78, child: Text(name, style: t.caption.copyWith(color: p.textMuted))),
            Expanded(child: Text(text, style: style)),
          ],
        ),
      );
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      role('display', t.display, 'Music'),
      role('greeting', t.greeting, 'नमस्ते'),
      role('screenTitle', t.screenTitle, 'रेशम फिरिरी Mix'),
      role('playerTitle', t.playerTitle, 'क्षितिज पारि · Audit_Long_Tone_5min'),
      role('cardTitle', t.cardTitle, 'झिलिमिली साँझ'),
      role('sectionTitle', t.sectionTitle, 'Recently played'),
      role('body', t.body, 'Body text Il1 O0 रेशम फिरिरी'),
      role('bodyStrong', t.bodyStrong, 'Song title क्षितिज पारि'),
      role('metadata', t.metadata, 'Artist · Album · 4:05 झिलिमिली'),
      role('label', t.label, 'Downloads'),
      role('chipLabel', t.chipLabel, 'Narayan Gopal'),
      role('button', t.button, 'Play all'),
      role('caption', t.caption, 'Helper fine print'),
      role('tabular', t.tabularFigures, '1:23  -2:41  1.2 GB'),
      role('index', t.index, '01 02 03'),
      role('overline', t.overline, 'NOW PLAYING · 3 / 24'),
      role('badge', t.badge, '1080P  MP3  12:48'),
      role('figureLarge', t.figureLarge, '42%'),
      gap(),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          VoltButton(label: 'Play all', icon: Icons.play_arrow_rounded, onPressed: () {}),
          VoltButton.compact(label: 'Download', icon: Icons.download_rounded, onPressed: () {}),
          const VoltButton(label: 'Disabled', onPressed: null),
          FilledButton(onPressed: () {}, child: const Text('Save')),
          FilledButton.tonal(onPressed: () {}, child: const Text('Shuffle')),
          OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.link_rounded), label: const Text('Copy link')),
          TextButton(onPressed: () {}, child: const Text('See all')),
          const FilledButton(onPressed: null, child: Text('Off')),
        ],
      ),
      gap(),
      Row(
        children: [
          VoltDisc(icon: Icons.play_arrow_rounded, size: VoltDisc.small, onPressed: () {}),
          const SizedBox(width: 8),
          VoltDisc(icon: Icons.play_arrow_rounded, size: VoltDisc.medium, onPressed: () {}),
          const SizedBox(width: 16),
          VoltDisc(icon: Icons.pause_rounded, size: VoltDisc.large, onPressed: () {}),
          const SizedBox(width: 16),
          const VoltDisc(icon: Icons.play_arrow_rounded, size: VoltDisc.medium, onPressed: null),
        ],
      ),
      gap(),
      VoltSlab(title: 'झिलिमिली साँझ', subtitle: 'Sabin Rai · 2:31 left', progress: 0.4, onTap: () {}, onPlay: () {}),
      gap(),
      VoltSlab(title: 'Audit_Long_Tone_5min_final_master', subtitle: 'Unknown artist', onTap: () {}, onPlay: () {}),
      gap(),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(label: const Text('Background play'), selected: true, onSelected: (_) {}),
          FilterChip(label: const Text('Auto PiP'), selected: false, onSelected: (_) {}),
          ChoiceChip(label: const Text('Audio  12'), selected: true, onSelected: (_) {}),
          ChoiceChip(
            avatar: const Icon(Icons.videocam_rounded),
            label: const Text('Video  3'),
            selected: false,
            onSelected: (_) {},
          ),
          const FilterChip(label: Text('Disabled'), selected: false, onSelected: null),
          const FilterChip(label: Text('Disabled on'), selected: true, onSelected: null),
        ],
      ),
      gap(),
      Wrap(
        children: [
          Switch(value: true, onChanged: (_) {}),
          Switch(value: false, onChanged: (_) {}),
          const Switch(value: true, onChanged: null),
          const Switch(value: false, onChanged: null),
          Checkbox(value: true, onChanged: (_) {}),
          Checkbox(value: false, onChanged: (_) {}),
        ],
      ),
      Slider(value: 0.4, onChanged: (_) {}),
      const LinearProgressIndicator(value: 0.6),
      gap(),
      const TextField(decoration: InputDecoration(hintText: 'Search songs', prefixIcon: Icon(Icons.search_rounded))),
      gap(),
      const TextField(decoration: InputDecoration(labelText: 'Link', errorText: 'That link does not work')),
      gap(),
      const SectionHeader(kicker: 'From your library', title: 'Recently played', actionLabel: 'See all', padding: EdgeInsets.zero),
      gap(),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          const PillTag(text: 'PRIMARY'),
          PillTag(text: 'VIDEO', color: p.accent),
          PillTag(text: 'FAV', color: p.favorite),
          PillTag(text: 'SAVED', color: p.success),
          PillTag(text: 'QUEUED', color: p.warning),
          PillTag(text: 'FAILED', color: p.error),
          PillTag(text: 'YOUTUBE', color: p.accent, onColor: p.onAccent, filled: true),
          PillTag(text: 'LIVE', color: p.liveFill, onColor: p.onLive, filled: true),
        ],
      ),
      gap(),
      SizedBox(
        height: 110,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.white)),
            const Positioned(left: 8, top: 8, child: MediaBadge(icon: Icons.download_done_rounded, text: 'Downloaded')),
            const Positioned(right: 8, bottom: 8, child: DurationBadge(duration: Duration(minutes: 12, seconds: 48))),
            const Positioned(left: 8, bottom: 8, child: DurationBadge.live()),
            const Positioned(
              right: 8,
              top: 8,
              width: 90,
              height: 60,
              child: ArtworkPlaceholder(seed: 'song_3', icon: Icons.music_note_rounded),
            ),
          ],
        ),
      ),
      gap(),
      SurfaceCard(onTap: () {}, child: Text('SurfaceCard: a settings group', style: t.body)),
      gap(),
      ListTile(title: const Text('ListTile title'), subtitle: const Text('Subtitle'), trailing: const Text('1.2 GB'), onTap: () {}),
      SizedBox(
        height: 420,
        child: EmptyHint(
          icon: Icons.music_note_rounded,
          kicker: 'Library',
          title: 'No songs yet',
          message: 'Paste a link to save a song.',
          action: VoltButton(label: 'Open Downloads', icon: Icons.download_rounded, onPressed: () {}),
        ),
      ),
    ],
  );
}

/// The Ink Dock with a stand-in mini player row and the five destinations.
Widget componentsDock() => InkDock(
      miniPlayer: SizedBox(
        height: InkDock.miniPlayerHeight,
        child: Builder(
          builder: (context) {
            final p = context.palette;
            final t = AppTypography.of(p);
            return Row(
              children: [
                const SizedBox(width: 12),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: p.surfacePressed, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('रेशम फिरिरी', style: t.bodyStrong.copyWith(color: p.onDock), maxLines: 1),
                      Text('Narayan Gopal', style: t.metadata.copyWith(color: p.onDockMuted), maxLines: 1),
                    ],
                  ),
                ),
                IconButton(onPressed: () {}, icon: const Icon(Icons.skip_previous_rounded, size: 28)),
                VoltDisc(icon: Icons.pause_rounded, size: VoltDisc.small, onPressed: () {}),
                IconButton(onPressed: () {}, icon: const Icon(Icons.skip_next_rounded, size: 28)),
                const SizedBox(width: 4),
              ],
            );
          },
        ),
      ),
      navigation: NavigationBar(
        selectedIndex: 3,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note_rounded),
            label: 'Music',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: 'Videos',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_display_outlined),
            selectedIcon: Icon(Icons.smart_display_rounded),
            label: 'Online',
          ),
          NavigationDestination(
            icon: Icon(Icons.file_download_outlined),
            selectedIcon: Icon(Icons.file_download_rounded),
            label: 'Downloads',
          ),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockRepo repo;
  late MockPerm perm;
  late MockPlaybackRepository playbackRepo;
  late AppDatabase db;

  final albums = [
    const AlbumGroup(album: 'Songs of the Hills', artist: 'Himal Sessions', songCount: 12, totalDurationMs: 1),
    const AlbumGroup(album: 'After Hours', artist: 'Neon Atlas Orchestra', songCount: 8, totalDurationMs: 1),
    const AlbumGroup(album: 'Home Tapes', artist: 'Family Recordings', songCount: 31, totalDurationMs: 1),
    const AlbumGroup(album: 'Tea Garden Stories (Deluxe Edition)', artist: 'The Ilam Collective', songCount: 14, totalDurationMs: 1),
  ];

  setUpAll(() async {
    registerFallbackValue(MediaSortOption.title);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(FakeAudioSource());
    registerFallbackValue(LoopMode.off);
    registerFallbackValue(FakePlaybackState());
    await loadFonts();
    Directory(outDir).createSync(recursive: true);
    brightCover = await brightCoverPng();
    warmCover = await warmCoverPng();
    final artDir = Directory.systemTemp.createTempSync('mediahub_preview_art');
    brightCoverPath = '${artDir.path}/bright_cover.png'.replaceAll(r'\', '/');
    File(brightCoverPath).writeAsBytesSync(brightCover);
    File('$outDir/_bright_cover_source.png').writeAsBytesSync(brightCover);
    File('$outDir/_warm_cover_source.png').writeAsBytesSync(warmCover);
    // ignore: avoid_print
    print('song palettes: ${songs.map((s) => ArtworkPlaceholder.paletteIndexFor(s.uri)).toList()}');
    // ignore: avoid_print
    print('video palettes: ${videos.map((s) => ArtworkPlaceholder.paletteIndexFor(s.uri)).toList()}');
    // ignore: avoid_print
    print('album palettes: ${albums.map((a) => ArtworkPlaceholder.paletteIndexFor(ArtworkPlaceholder.albumSeed(a.album))).toList()}');
  });

  setUp(() {
    clearDeviceArt();
    // Like a phone, a device-art lookup answers (with nothing) at once, so
    // tinted surfaces settle on their placeholder palette. Without a handler
    // the call would wait on the real event loop and never answer in a
    // scene's fake time.
    mockDeviceArt(const {});
    db = AppDatabase(NativeDatabase.memory());
    repo = MockRepo();
    perm = MockPerm();
    playbackRepo = MockPlaybackRepository();
    when(() => playbackRepo.loadLastPlaybackState()).thenAnswer((_) async => null);
    when(() => playbackRepo.savePlaybackState(any())).thenAnswer((_) async {});
    when(() => perm.checkAudioPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => perm.checkVideoPermission()).thenAnswer((_) async => MediaPermissionState.granted);
    when(() => repo.scanDeviceMedia()).thenAnswer((_) async {});
    when(() => repo.watchMediaItems(
          mediaType: MediaType.audio,
          searchQuery: any(named: 'searchQuery'),
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
        )).thenAnswer((_) => Stream.value(songs));
    when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(albums));
    when(() => repo.watchArtists(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchPlaylists()).thenAnswer((_) => Stream.value(const []));
    when(() => repo.watchFavorites(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(songs));
    when(() => repo.watchAlbumSongs(any())).thenAnswer((_) => Stream.value(songs.take(6).toList()));
    when(() => repo.watchArtistSongs(any())).thenAnswer((_) => Stream.value(songs));
  });

  tearDown(() async {
    clearDeviceArt();
    await db.close();
  });

  void phone(WidgetTester tester, {double width = 360, double height = 800, double textScale = 1}) {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
  }

  Widget app(Widget home, {domain.PlaybackState? state, List overrides = const [], LibraryRepository? library}) => ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(library ?? repo),
          mediaPermissionServiceProvider.overrideWithValue(perm),
          appDatabaseProvider.overrideWithValue(db),
          audioHandlerProvider.overrideWithValue(makeHandler()),
          playbackRepositoryProvider.overrideWithValue(playbackRepo),
          if (state != null) playbackNotifierProvider.overrideWith(() => FakePlayback(state)),
          throttledPositionStreamProvider.overrideWith((ref) => Stream.value(const Duration(seconds: 74))),
          isFavoriteProvider.overrideWith((ref, id) => Stream.value(id == 'song_0' || id == 'song_3')),
          ...overrides.cast(),
        ],
        child: RepaintBoundary(
          key: shotKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: previewThemeData,
            home: home,
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets real covers load: file reads, platform-channel bytes, image
  /// decoding and the Now Playing swatch all need the real event loop, so
  /// real time and fake frames alternate, then every Image on screen is
  /// precached and the fade-ins run to the end.
  Future<void> settleArt(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  }

  void scenes() {
    testWidgets('music_list', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
      await settle(tester);
      await shot(tester, 'music_list');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('music_list_320', (tester) async {
      phone(tester, width: 320);
      await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
      await settle(tester);
      await shot(tester, 'music_list_320');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('music_list_text13', (tester) async {
      phone(tester, textScale: 1.3);
      await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
      await settle(tester);
      await shot(tester, 'music_list_text13');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('music_list_art', (tester) async {
      // Two songs with embedded covers among placeholders.
      phone(tester);
      mockDeviceArt({songs[0].uri: warmCover, songs[3].uri: brightCover});
      await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
      await settleArt(tester);
      await shot(tester, 'music_list_art');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('music_empty', (tester) async {
      phone(tester);
      when(() => repo.watchMediaItems(
            mediaType: MediaType.audio,
            searchQuery: any(named: 'searchQuery'),
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
          )).thenAnswer((_) => Stream.value(const []));
      await tester.pumpWidget(app(const MusicScreen()));
      await settle(tester);
      await shot(tester, 'music_empty');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('mini_player_and_list', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(
        const Scaffold(
          body: MusicScreen(),
          bottomNavigationBar: SafeArea(child: MiniPlayer()),
        ),
        state: playing(4),
      ));
      await settle(tester);
      await shot(tester, 'mini_player_and_list');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    // a: song 0's palette. b: a song on another palette (flare, ultraviolet,
    // orchid or ember, if any song lands there). jade: the eighth entry.
    final npB = songWithPalette([2, 0, 6, 4], other: 0);
    final npJade = songs.indexWhere((s) => ArtworkPlaceholder.paletteIndexFor(s.uri) == 7);
    for (final (name, index) in [
      ('now_playing_a', 0),
      ('now_playing_b', npB),
      if (npJade >= 0) ('now_playing_jade', npJade),
    ]) {
      testWidgets(name, (tester) async {
        // ignore: avoid_print
        print('$name: song $index, palette ${ArtworkPlaceholder.paletteIndexFor(songs[index].uri)}');
        phone(tester);
        await tester.pumpWidget(app(const NowPlayingSheet(), state: playing(index)));
        await settle(tester);
        await shot(tester, name);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('now_playing_bright', (tester) async {
      // A real, mostly white cover from a saved file: header and caption
      // contrast over the blurred cover.
      phone(tester);
      final queue = [
        for (var i = 0; i < songs.length; i++)
          i == 3 ? songs[i].copyWith(artworkPath: brightCoverPath) : songs[i],
      ];
      await tester.pumpWidget(app(const NowPlayingSheet(), state: playingFrom(queue, 3)));
      await settleArt(tester);
      await shot(tester, 'now_playing_bright');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('now_playing_warm_art', (tester) async {
      // Embedded (device) art, warm red: the glow should go neutral.
      phone(tester);
      mockDeviceArt({songs[4].uri: warmCover});
      await tester.pumpWidget(app(const NowPlayingSheet(), state: playing(4)));
      await settleArt(tester);
      await shot(tester, 'now_playing_warm_art');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('now_playing_text13', (tester) async {
      // Longest title at 1.3x text.
      phone(tester, textScale: 1.3);
      await tester.pumpWidget(app(const NowPlayingSheet(), state: playing(6)));
      await settle(tester);
      await shot(tester, 'now_playing_text13');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('queue', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  clipBehavior: Clip.antiAlias,
                  builder: (_) => const FractionallySizedBox(heightFactor: 0.7, child: QueueSheet()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        state: playing(2),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await shot(tester, 'queue');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('home', (tester) async {
      phone(tester);
      tester.view.physicalSize = const Size(360 * 3, 1640 * 3);
      await tester.pumpWidget(app(
        const HomeScreen(),
        state: playing(1, isPlaying: false),
        library: HomeRepo(songs, videos),
      ));
      await settle(tester);
      await shot(tester, 'home');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('home_real_art', (tester) async {
      // The "Continue listening" song has an embedded warm cover: the card
      // should switch to the neutral hero gradient.
      phone(tester);
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      mockDeviceArt({songs[1].uri: warmCover, songs[0].uri: brightCover});
      await tester.pumpWidget(app(
        const HomeScreen(),
        state: playing(1, isPlaying: false),
        library: HomeRepo(songs, videos),
      ));
      await settleArt(tester);
      await shot(tester, 'home_real_art');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('videos', (tester) async {
      phone(tester);
      tester.view.physicalSize = const Size(360 * 3, 1300 * 3);
      final state = LibraryState(
        permissionState: MediaPermissionState.granted,
        status: LibraryStatus.success,
        items: videos,
      );
      await tester.pumpWidget(app(
        const VideosScreen(),
        overrides: [
          videoLibraryProvider.overrideWith(() => FakeVideoNotifier(state)),
          allVideoProgressStreamProvider.overrideWith((ref) => Stream.value([
                VideoProgress(mediaId: 'video_0', positionMs: 1500000, durationMs: 3723000, updatedAt: DateTime.now()),
                VideoProgress(mediaId: 'video_3', positionMs: 120000, durationMs: 418000, updatedAt: DateTime.now()),
              ])),
        ],
      ));
      await settle(tester);
      await shot(tester, 'videos');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('videos_downloaded_bright', (tester) async {
      // A downloaded video whose saved thumbnail is nearly white, first in
      // the list: the "Downloaded" and duration badges over a bright frame.
      phone(tester);
      final items = [
        videos[2].copyWith(artworkPath: brightCoverPath),
        videos[0],
        videos[1],
      ];
      final state = LibraryState(
        permissionState: MediaPermissionState.granted,
        status: LibraryStatus.success,
        items: items,
      );
      await tester.pumpWidget(app(
        const VideosScreen(),
        overrides: [
          videoLibraryProvider.overrideWith(() => FakeVideoNotifier(state)),
          allVideoProgressStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      ));
      await settleArt(tester);
      await shot(tester, 'videos_downloaded_bright');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    // Small phones and large text (docs/DESIGN.md 10.6 and open risk 4).
    for (final (name, width, height, scale) in [
      ('home_320', 320.0, 1640.0, 1.0),
      ('home_text13', 360.0, 2000.0, 1.3),
    ]) {
      testWidgets(name, (tester) async {
        phone(tester, width: width, height: height, textScale: scale);
        await tester.pumpWidget(app(
          const HomeScreen(),
          state: playing(1, isPlaying: false),
          library: HomeRepo(songs, videos),
        ));
        await settle(tester);
        await shot(tester, name);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('videos_320', (tester) async {
      phone(tester, width: 320, height: 1300);
      final state = LibraryState(
        permissionState: MediaPermissionState.granted,
        status: LibraryStatus.success,
        items: videos,
      );
      await tester.pumpWidget(app(
        const VideosScreen(),
        overrides: [
          videoLibraryProvider.overrideWith(() => FakeVideoNotifier(state)),
          allVideoProgressStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      ));
      await settle(tester);
      await shot(tester, 'videos_320');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    // The foundation pieces on one tall sheet, over the Ink Dock.
    for (final (name, width, height, scale) in [
      ('components', 360.0, 2900.0, 1.0),
      ('components_320', 320.0, 3100.0, 1.0),
      ('components_text13', 360.0, 3700.0, 1.3),
    ]) {
      testWidgets(name, (tester) async {
        phone(tester, width: width, height: height, textScale: scale);
        await tester.pumpWidget(app(
          Scaffold(body: Builder(builder: componentsSheet), bottomNavigationBar: componentsDock()),
        ));
        await settle(tester);
        await shot(tester, name);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('dialog_snackbar', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Sent to Downloads'), action: SnackBarAction(label: 'View', onPressed: () {})),
                  );
                  showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete download?'),
                      content: const Text('रेशम फिरिरी.mp3 will be removed from this phone.'),
                      actions: [
                        TextButton(onPressed: () {}, child: const Text('Cancel')),
                        FilledButton(onPressed: () {}, child: const Text('Delete')),
                      ],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
      await shot(tester, 'dialog_snackbar');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    /// The Online tab on a watch page, over a stand-in WebView (platform
    /// views do not render in flutter test): toolbar, address pill and the
    /// watch strip.
    Future<void> pumpOnline(WidgetTester tester) async {
      await SettingsStore.instance.setBool(OnlineBackgroundPlayNotifier.prefKey, true);
      await SettingsStore.instance.setBool(OnlineAutoPipNotifier.prefKey, false);
      PlatformInfo.debugIsAndroid = true; // the Download button is phone-only
      addTearDown(PlatformInfo.resetForTests);
      final web = FakeOnlineWebView();
      final host = FakeExternalHost();
      await tester.pumpWidget(app(
        const Scaffold(body: OnlineScreen()),
        overrides: [
          onlineWebViewBuilderProvider.overrideWithValue(web.builder),
          onlineAssetsProvider.overrideWith((ref) async => fakeOnlineAssets),
          androidSdkIntProvider.overrideWith((ref) async => 34),
          onlineMediaSessionProvider.overrideWith((ref) {
            final session = OnlineMediaSession(host: host);
            ref.onDispose(session.dispose);
            return session;
          }),
          onlineExternalLauncherProvider.overrideWithValue((uri) async {}),
          onlineDataClearerProvider.overrideWithValue(() async {}),
        ],
      ));
      await tester.pump();
      await tester.pump();
      web.navigate(
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'झिलिमिली साँझ - Official Video - YouTube',
      );
      await settle(tester);
    }

    for (final (name, width, scale) in [
      ('online_watch', 360.0, 1.0),
      ('online_watch_320', 320.0, 1.0),
      ('online_watch_text13', 360.0, 1.3),
    ]) {
      testWidgets(name, (tester) async {
        phone(tester, width: width, textScale: scale);
        await pumpOnline(tester);
        await shot(tester, name);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }

    testWidgets('online_menu', (tester) async {
      phone(tester);
      await pumpOnline(tester);
      await tester.tap(find.byKey(const ValueKey('online_menu')));
      await settle(tester);
      await shot(tester, 'online_menu');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('album_detail', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(AlbumDetailScreen(album: albums.first), state: playing(3)));
      await settle(tester);
      await shot(tester, 'album_detail');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('albums_grid', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
      await settle(tester);
      await tester.tap(find.text('Albums'));
      await settle(tester);
      await shot(tester, 'albums_grid');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    // The same album, with a real embedded cover, on its grid tile and on its
    // detail page: both should show the same cover, and the header should
    // drop the hash tint for the neutral one.
    final artAlbums = [
      AlbumGroup(
        album: albums[0].album,
        artist: albums[0].artist,
        songCount: 6,
        totalDurationMs: 1,
        coverUri: songs[0].uri,
      ),
      ...albums.skip(1),
    ];

    testWidgets('albums_grid_art', (tester) async {
      phone(tester);
      mockDeviceArt({songs[0].uri: warmCover});
      // Plus downloads (no album tag): their tile shows the cover song's
      // saved thumbnail file, as their album page does. Second, so it is in
      // the shot (the real list sorts it last).
      final withDownloads = [
        artAlbums.first,
        AlbumGroup(
          album: 'Unknown Album',
          artist: 'Mountain Bridges',
          songCount: 3,
          totalDurationMs: 1,
          coverUri: 'file:///storage/emulated/0/Music/MediaHub/folk_session.m4a',
          coverArtworkPath: brightCoverPath,
        ),
        ...artAlbums.skip(1),
      ];
      when(() => repo.watchAlbums(searchQuery: any(named: 'searchQuery'))).thenAnswer((_) => Stream.value(withDownloads));
      await tester.pumpWidget(app(const MusicScreen(), state: playing(2)));
      await settle(tester);
      await tester.tap(find.text('Albums'));
      await settleArt(tester);
      await shot(tester, 'albums_grid_art');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('album_detail_art', (tester) async {
      phone(tester);
      mockDeviceArt({songs[0].uri: warmCover});
      await tester.pumpWidget(app(AlbumDetailScreen(album: artAlbums.first), state: playing(3)));
      await settleArt(tester);
      await shot(tester, 'album_detail_art');
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  for (final theme in previewThemes) {
    group(theme, () {
      setUp(() => previewTheme = theme);
      scenes();
    });
  }
}
