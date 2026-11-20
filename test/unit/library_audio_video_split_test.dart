// Audio in Music, video in Videos (P3, task 4). The owner: "video downloads
// stay in the video section and audio in the music section". One audio and
// one video download with the same title and channel, both liked and played:
// Songs, Albums, Artists, Favourites, the playlist "Add songs" list and the
// Home song rails show only the song; the Videos tab and the Home video rail
// show only the video. A phone scan does not mix them either.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';

/// Answers queryAudio / queryVideo like MediaStore would (one of each).
class _FakeMediaStore implements MethodChannel {
  @override
  String get name => 'mediahub/media_store';

  @override
  Future<List<T>?> invokeListMethod<T>(String method, [dynamic arguments]) async {
    final row = <String, Object?>{
      'id': '7',
      'title': method == 'queryAudio' ? 'Phone song' : 'Phone clip',
      'artist': 'Sajjan Raj Vaidya',
      'durationMs': 200000,
      'sizeBytes': 1000,
      'dateAdded': 1700000000,
    };
    if (method == 'queryAudio') return [row..['uri'] = 'content://media/external/audio/media/7'].cast<T>();
    if (method == 'queryVideo') return [row..['uri'] = 'content://media/external/video/media/7'].cast<T>();
    return null;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  const song = 'dl_song';
  const clip = 'dl_clip';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(db, _FakeMediaStore());
    final now = DateTime.now();
    for (final (id, type, ext) in [(song, MediaType.audio, 'm4a'), (clip, MediaType.video, 'mp4')]) {
      // As the download engines write them: no search key, no album.
      await db.into(db.mediaItemsTable).insert(
            MediaItemsTableCompanion.insert(
              id: id,
              uri: '/data/user/0/app/downloads/Resham Firiri.$ext',
              mediaType: type.name,
              title: 'Resham Firiri',
              artist: const Value('Sajjan Raj Vaidya'),
              durationMs: 0,
              sizeBytes: 4000,
              format: Value(ext),
              dateAdded: now,
              availability: const Value('available'),
              source: const Value('download'),
              isFavorite: const Value(true),
              favoritedAt: Value(now),
              playCount: const Value(3),
              lastPlayed: Value(now),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  List<String> ids(List<MediaItem> items) => [for (final i in items) i.id];

  Future<void> expectSplit(LibraryRepository repo, {required String reason}) async {
    // The Music tab.
    expect(ids(await repo.watchSongs().first), [song], reason: 'Songs: $reason');
    expect(ids(await repo.watchSongs(searchQuery: 'resham').first), [song], reason: 'Songs search: $reason');
    expect(ids(await repo.watchMediaItems(mediaType: MediaType.audio).first), [song], reason: reason);
    final albums = await repo.watchAlbums().first;
    expect([for (final a in albums) a.songCount], [1], reason: 'Albums count only the song: $reason');
    expect(ids(await repo.watchAlbumSongs(albums.single.key).first), [song], reason: 'album page: $reason');
    final artists = await repo.watchArtists().first;
    expect([for (final a in artists) (a.artist, a.songCount)], [('Sajjan Raj Vaidya', 1)], reason: reason);
    expect(ids(await repo.watchArtistSongs('Sajjan Raj Vaidya').first), [song], reason: 'artist page: $reason');
    expect(ids(await repo.watchFavorites().first), [song], reason: 'Favourites: $reason');
    expect(ids(await repo.watchFavorites(searchQuery: 'resham').first), [song], reason: reason);

    // The Videos tab.
    expect(ids(await repo.watchMediaItems(mediaType: MediaType.video).first), [clip], reason: 'Videos: $reason');
    expect(ids(await repo.watchMediaItems(mediaType: MediaType.video, searchQuery: 'resham').first), [clip],
        reason: 'Videos search: $reason');
    expect(ids(await repo.getMediaItems(mediaType: MediaType.video)), [clip], reason: reason);

    // Home: the song rails and the video rail.
    expect(ids(await repo.watchRecentlyPlayed().first), [song], reason: 'Recently played: $reason');
    expect(ids(await repo.watchMostPlayed().first), [song], reason: 'Most played: $reason');
    expect(ids(await repo.watchRecentlyAdded(mediaType: MediaType.audio).first), [song], reason: reason);
    expect(ids(await repo.watchRecentlyAdded().first), [song], reason: 'Recently added is songs by default');
    expect(ids(await repo.watchRecentVideos().first), [clip], reason: 'Recent videos: $reason');
  }

  test('a song download is only in Music, a video download only in Videos', () async {
    await expectSplit(repo, reason: 'two downloads');
  });

  test('a phone scan keeps them apart (and adds its own song and video to the right tab)', () async {
    await repo.scanDeviceMedia();
    expect(ids(await repo.watchSongs().first), unorderedEquals(['audio_7', song]));
    expect(ids(await repo.watchMediaItems(mediaType: MediaType.video).first), unorderedEquals(['video_7', clip]));
    final rows = {for (final r in await db.select(db.mediaItemsTable).get()) r.id: r.mediaType};
    expect(rows[song], 'audio');
    expect(rows[clip], 'video');
  });
}
