// Probes for the v8 library (fix plan P2): album identity and track order,
// search (several words, accents, LIKE wildcards, Devanagari), Favourites,
// playlists after a deleted download, missing files, online items and the
// scan's own bookkeeping. Each test is the shape of a bug it would have
// caught.
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/database/search_text.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playlist_and_groups.dart';

/// Answers queryAudio / queryVideo like MediaStore would.
class _FakeMediaStore implements MethodChannel {
  List<Map<String, Object?>> audio = [];
  List<Map<String, Object?>> video = [];
  String? generation;

  @override
  String get name => 'mediahub/media_store';

  @override
  Future<List<T>?> invokeListMethod<T>(String method, [dynamic arguments]) async {
    if (method == 'queryAudio') return audio.cast<T>();
    if (method == 'queryVideo') return video.cast<T>();
    return null;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (method == 'mediaGeneration') return generation as T?;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _track(
  String id,
  String title, {
  String? artist = 'Artist',
  String? album,
  String? albumId,
  String? albumArtist,
  int? track,
  int? year,
  int size = 1000,
  int durationMs = 200000,
  int dateAdded = 1700000000,
}) =>
    {
      'id': id,
      'uri': 'content://media/external/audio/media/$id',
      'title': title,
      'artist': artist,
      'album': album,
      'albumId': albumId,
      'albumArtist': albumArtist,
      'track': track,
      'year': year,
      'sizeBytes': size,
      'durationMs': durationMs,
      'dateAdded': dateAdded,
      'mimeType': 'audio/mpeg',
    };

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repo;
  late _FakeMediaStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = _FakeMediaStore();
    repo = LibraryRepositoryImpl(db, store);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertRow(
    String id, {
    String title = 'Song',
    String? artist = 'Artist',
    String? album,
    String type = 'audio',
    String source = 'device',
    String availability = 'available',
    bool favorite = false,
    bool withKey = true,
    int playCount = 0,
  }) {
    return db.into(db.mediaItemsTable).insert(
          MediaItemsTableCompanion.insert(
            id: id,
            uri: source == 'online' ? 'https://www.youtube.com/watch?v=$id' : 'content://media/$id',
            mediaType: type,
            title: title,
            artist: Value(artist),
            album: Value(album),
            durationMs: 1000,
            sizeBytes: 1,
            dateAdded: DateTime(2026),
            source: Value(source),
            availability: Value(availability),
            isFavorite: Value(favorite),
            playCount: Value(playCount),
            searchKey: Value(withKey ? librarySearchKey(title: title, artist: artist, album: album) : null),
          ),
        );
  }

  List<String> ids(List<MediaItem> items) => [for (final i in items) i.id];

  group('search folding', () {
    test('lowercases, drops Latin accents, keeps Devanagari as typed', () {
      expect(foldForSearch('Beyoncé'), 'beyonce');
      expect(foldForSearch('ÉTÉ'), 'ete');
      expect(foldForSearch('été'), foldForSearch('ÉTÉ'));
      expect(foldForSearch('Ñandú  Çava Øre'), 'nandu cava ore');
      // Already decomposed input (e + combining acute) folds the same way.
      expect(foldForSearch('été'), 'ete');
      // Devanagari vowel signs and virama stay: they are part of the word.
      expect(foldForSearch('नेपाली गीत'), 'नेपाली गीत');
      // Precomposed nukta letters match their two-character spelling.
      expect(foldForSearch('ज़'), 'ज़');
      expect(searchTerms('  Queen   Bohemian '), ['queen', 'bohemian']);
      expect(searchTerms('   '), isEmpty);
    });

    test('LIKE patterns escape %, _ and the escape character', () {
      expect(likeContainsPattern('100%'), r'%100\%%');
      expect(likeContainsPattern('h_lo'), r'%h\_lo%');
      expect(likeContainsPattern(r'a\b'), r'%a\\b%');
    });
  });

  group('search (LIB-06)', () {
    setUp(() async {
      await insertRow('q1', title: 'Bohemian Rhapsody', artist: 'Queen', album: 'A Night at the Opera');
      await insertRow('q2', title: 'Radio Ga Ga', artist: 'Queen', album: 'The Works');
      await insertRow('b1', title: 'Halo', artist: 'Beyoncé', album: 'I Am... Sasha Fierce');
      await insertRow('e1', title: 'Été indien', artist: 'Joe Dassin');
      await insertRow('p1', title: '100% Pure Love', artist: 'Crystal Waters');
      await insertRow('p2', title: '1000 Miles', artist: 'Vanessa');
      await insertRow('u1', title: 'h_lo remix', artist: 'DJ');
      await insertRow('n1', title: 'रेशम फिरिरी', artist: 'नेपाली लोक गीत', album: 'लोक');
      await insertRow('n2', title: 'ज़िंदगी', artist: 'Arijit');
    });

    Future<List<String>> search(String q) async =>
        ids(await repo.watchMediaItems(mediaType: MediaType.audio, searchQuery: q).first);

    test('every word has to match, in any field', () async {
      expect(await search('queen bohemian'), ['q1'], reason: 'used to search for the whole phrase');
      expect(await search('bohemian queen'), ['q1']);
      expect(await search('queen works'), ['q2']);
      expect(await search('queen zzz'), isEmpty);
    });

    test('accents and case are ignored both ways', () async {
      expect(await search('beyonce'), ['b1']);
      expect(await search('BEYONCÉ'), ['b1']);
      expect(await search('été'), ['e1']);
      expect(await search('ÉTÉ'), ['e1']);
      expect(await search('ete'), ['e1']);
    });

    test('% and _ are matched as themselves', () async {
      expect(await search('100%'), ['p1'], reason: '"1000 Miles" must not match');
      expect(await search('h_lo'), ['u1'], reason: '"Halo" must not match');
    });

    test('Devanagari substrings and both nukta spellings match', () async {
      expect(await search('रेशम'), ['n1']);
      expect(await search('फिरि'), ['n1']);
      expect(await search('लोक गीत'), ['n1'], reason: 'two words, both in the artist');
      expect(await search('ज़ि'), ['n2'], reason: 'ज + nukta finds the precomposed ज़');
    });

    test('Nepali spelling variants: chandrabindu or anusvara, Devanagari or ASCII digits (review)', () async {
      await insertRow('n3', title: 'साँझ', artist: 'नारायण गोपाल');
      await insertRow('n4', title: 'गीत २', artist: 'लोक');
      await insertRow('n5', title: 'Mix 2', artist: 'DJ');
      expect(foldForSearch('साँझ'), 'सांझ');
      expect(foldForSearch('२०८२'), '2082');
      expect(await search('सांझ'), ['n3'], reason: 'anusvara typed, chandrabindu stored');
      expect(await search('साँझ'), ['n3']);
      expect(await search('गीत 2'), ['n4'], reason: 'ASCII digit typed, Devanagari digit stored');
      expect(await search('mix २'), ['n5'], reason: 'and the other way round');
    });

    test('keys made by older folding rules are rebuilt before the search', () async {
      // As the first v8 builds stored it: no version tag, chandrabindu kept.
      await db.into(db.mediaItemsTable).insert(MediaItemsTableCompanion.insert(
            id: 'old1',
            uri: 'content://media/old1',
            mediaType: 'audio',
            title: 'साँझ पख',
            durationMs: 1000,
            sizeBytes: 1,
            dateAdded: DateTime(2026),
            searchKey: const Value('साँझ पख\n\n'),
          ));
      expect(await search('सांझ'), ['old1']);
      final row = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('old1'))).getSingle();
      expect(isCurrentSearchKey(row.searchKey), isTrue);
      expect(row.searchKey, contains('सांझ पख'));
    });

    test('romanised Latin words find Devanagari titles, artists and albums (review)', () async {
      await insertRow('n6', title: 'साँझ पख', artist: 'नारायण गोपाल');
      await insertRow('n7', title: 'विश्वास', artist: 'Sabin Rai');
      await insertRow('e2', title: 'Mundane', artist: 'Band');
      expect(await search('resham'), ['n1']);
      expect(await search('resham firiri'), ['n1']);
      expect(await search('phiriri'), ['n1'], reason: 'ph and f, both ways');
      expect(await search('nepali geet'), ['n1'], reason: 'ee for ई, in the artist');
      expect(await search('sanjh'), ['n6'], reason: 'the chandrabindu read as n, long aa as a');
      expect(await search('saanjh narayan'), ['n6']);
      expect(await search('bishwas'), ['n7'], reason: 'व written w, v or b');
      expect(await search('biswas sabin'), ['n7'], reason: 'one word romanised, one as written');
      expect(await search('moon'), isEmpty, reason: '"mun" loosened must not find the English "Mundane"');
      expect(await search('mundane'), ['e2']);
      expect(await search('ma'), isEmpty, reason: 'too short to look for in romanised form');
      final artists = await repo.watchArtists(searchQuery: 'narayan gopal').first;
      expect(artists.map((a) => a.artist), ['नारायण गोपाल']);
      final albums = await repo.watchAlbums(searchQuery: 'lok').first;
      expect(albums.map((a) => a.album), ['लोक']);
    });

    test('romanisation helpers', () {
      expect(romanSkeleton(transliterateDevanagari('रेशम')), romanSkeleton('resham'));
      expect(romanSkeleton(transliterateDevanagari('प्यार')), romanSkeleton('pyaar'));
      expect(romanSkeleton(transliterateDevanagari('कृष्ण')), romanSkeleton('krishna'));
      expect(romanSkeleton('Sapana'), romanSkeleton('sapna'));
      expect(romanSearchField('queen'), isNull, reason: 'only Devanagari fields get one');
      expect(romanTermPattern('h_lo'), isNull);
      expect(romanTermPattern('a'), isNull);
      expect(matchesAllTerms(['resham'], [foldForSearch('रेशम फिरिरी')]), isTrue);
      expect(matchesAllTerms(['resham'], [foldForSearch('Resham Mix')]), isTrue);
      expect(matchesAllTerms(['moon'], [foldForSearch('Mundane')]), isFalse);
    });

    test('a search term can never match the key version tag', () async {
      expect(searchTerms(searchKeyVersionTag), isEmpty);
      expect(isCurrentSearchKey(librarySearchKey(title: 'x')), isTrue);
      expect(await search('$searchKeyVersionTag queen'), ['q1', 'q2']);
    });

    test('a row without a search key yet (just downloaded) is still found, and gets its key', () async {
      await insertRow('d1', title: 'Fresh Download', artist: 'Uploader', source: 'download', withKey: false);
      expect(await search('fresh download'), ['d1']);
      final row = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('d1'))).getSingle();
      expect(row.searchKey, isNotNull, reason: 'filled before the search ran');
    });

    test('albums and artists search every word too', () async {
      final albums = await repo.watchAlbums(searchQuery: 'queen opera').first;
      expect(albums.map((a) => a.album), ['A Night at the Opera']);
      final artists = await repo.watchArtists(searchQuery: 'beyonce').first;
      expect(artists.map((a) => a.artist), ['Beyoncé']);
    });
  });

  group('albums (LIB-01, LIB-02)', () {
    test('two albums with the same name stay apart; one compilation stays together', () async {
      store.audio = [
        _track('1', 'Intro', album: 'Greatest Hits', albumId: '10', artist: 'Queen', track: 1),
        _track('2', 'Outro', album: 'Greatest Hits', albumId: '10', artist: 'Queen', track: 2),
        _track('3', 'Hello', album: 'Greatest Hits', albumId: '20', artist: 'Lionel Richie', track: 1),
        _track('4', 'Song A', album: 'Now 50', albumId: '30', artist: 'Adele', albumArtist: 'Various Artists'),
        _track('5', 'Song B', album: 'Now 50', albumId: '30', artist: 'Drake', albumArtist: 'Various Artists'),
        _track('6', 'Song C', album: 'Mixed', albumId: '40', artist: 'Adele'),
        _track('7', 'Song D', album: 'Mixed', albumId: '40', artist: 'Drake'),
      ];
      await repo.scanDeviceMedia();

      final albums = await repo.watchAlbums().first;
      final hits = albums.where((a) => a.album == 'Greatest Hits').toList();
      expect(hits, hasLength(2), reason: 'used to merge into one 3-song album');
      expect(hits.map((a) => a.artist), unorderedEquals(['Queen', 'Lionel Richie']));
      final now = albums.singleWhere((a) => a.album == 'Now 50');
      expect(now.songCount, 2, reason: 'a compilation used to split per artist');
      expect(now.artist, 'Various Artists', reason: 'the album-artist tag wins');
      expect(albums.singleWhere((a) => a.album == 'Mixed').artist, AlbumGroup.variousArtists);
      expect(albums.map((a) => a.key).toSet(), hasLength(albums.length), reason: 'keys are unique');

      final queen = hits.singleWhere((a) => a.artist == 'Queen');
      expect(ids(await repo.watchAlbumSongs(queen.lookupKey).first), ['audio_1', 'audio_2']);
    });

    test('songs play in disc and track order, untagged last; the year is kept', () async {
      store.audio = [
        _track('1', 'Alpha', album: 'Double', albumId: '7', track: 2003, year: 2019),
        _track('2', 'Bravo', album: 'Double', albumId: '7', track: 1001, year: 2019),
        _track('3', 'Charlie', album: 'Double', albumId: '7', track: 2001),
        _track('4', 'Delta', album: 'Double', albumId: '7'),
        _track('5', 'Echo', album: 'Double', albumId: '7', track: 1002),
      ];
      await repo.scanDeviceMedia();
      final album = (await repo.watchAlbums().first).single;
      expect(album.year, 2019);
      final songs = await repo.watchAlbumSongs(album.lookupKey).first;
      expect([for (final s in songs) s.title], ['Bravo', 'Echo', 'Charlie', 'Alpha', 'Delta'],
          reason: 'used to be A-Z');
      expect([for (final s in songs) s.trackNumber], [1, 2, 1, 3, null]);
      expect([for (final s in songs) s.discNumber], [1, 1, 2, 2, null]);
      expect(LibraryRepositoryImpl.splitTrackNumber(2005), (2, 5));
      expect(LibraryRepositoryImpl.splitTrackNumber(7), (null, 7));
      expect(LibraryRepositoryImpl.splitTrackNumber(0), (null, null));
    });

    test('downloads group by album and artist, and "Go to album" finds the same group', () async {
      await insertRow('d1', title: 'One', artist: 'Uploader', album: null, source: 'download');
      await insertRow('d2', title: 'Two', artist: 'Uploader', album: null, source: 'download');
      await insertRow('d3', title: 'Three', artist: 'Someone else', album: null, source: 'download');
      final albums = await repo.watchAlbums().first;
      expect(albums, hasLength(2));
      final row = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('d1'))).getSingle();
      final found = await repo.findAlbumOf(row.toDomain());
      expect(found?.songCount, 2);
      expect(ids(await repo.watchAlbumSongs(found!.lookupKey).first), ['d1', 'd2']);
    });
  });

  group('unknown artist (LIB-05)', () {
    test('the scan stores NULL, and one "Unknown artist" tile opens every untagged song', () async {
      store.audio = [
        _track('1', 'A', artist: '<unknown>'),
        _track('2', 'B', artist: 'Unknown Artist'),
        _track('3', 'C', artist: null),
        _track('4', 'D', artist: 'Real'),
      ];
      await repo.scanDeviceMedia();
      final stored = await db.select(db.mediaItemsTable).get();
      expect(stored.where((r) => r.artist == null), hasLength(3));

      // A row from an older version that still says "Unknown Artist".
      await insertRow('legacy', title: 'E', artist: 'Unknown Artist');

      final artists = await repo.watchArtists().first;
      expect(artists.where((a) => a.isUnknown), hasLength(1), reason: 'one tile only');
      expect(artists.last.artist, ArtistGroup.unknownArtist);
      expect(artists.last.songCount, 4);
      final songs = await repo.watchArtistSongs(ArtistGroup.unknownArtist).first;
      expect(songs, hasLength(4), reason: 'the tile used to open an empty page');
      expect(await repo.watchArtistSongs('Unknown Artist').first, hasLength(4));
    });
  });

  group('playlists (SEC-1, LIB-10, LIB-16)', () {
    test('a deleted download leaves no orphan: count, remove and reorder stay right', () async {
      for (final id in ['a', 'b', 'c']) {
        await insertRow(id, title: id);
      }
      final pl = await repo.createPlaylist('Mix');
      for (final id in ['a', 'b', 'c']) {
        await repo.addSongToPlaylist(pl.id, id);
      }
      await repo.deleteMediaCompletely('b');

      final playlist = (await repo.watchPlaylists().first).single;
      expect(playlist.songCount, 2, reason: 'used to say 3 with 2 shown');
      final tracks = await repo.watchPlaylistTracks(pl.id).first;
      expect([for (final t in tracks) (t.item.id, t.position)], [('a', 0), ('c', 1)]);

      await repo.reorderPlaylist(pl.id, tracks[1].position, tracks[0].position);
      expect(ids(await repo.watchPlaylistSongs(pl.id).first), ['c', 'a']);
      final moved = await repo.watchPlaylistTracks(pl.id).first;
      await repo.removeSongFromPlaylist(pl.id, 'a', moved[1].position);
      expect(ids(await repo.watchPlaylistSongs(pl.id).first), ['c']);
    });

    test('with an orphan still in the table (count 3, visible 2), remove and drag act on the real entry', () async {
      for (final id in ['a', 'b', 'c']) {
        await insertRow(id, title: id);
      }
      final pl = await repo.createPlaylist('Mix');
      for (final id in ['a', 'b', 'c']) {
        await repo.addSongToPlaylist(pl.id, id);
      }
      // The old download delete: the song row went, its entry stayed.
      await (db.delete(db.mediaItemsTable)..where((t) => t.id.equals('b'))).go();

      expect((await repo.watchPlaylists().first).single.songCount, 2, reason: 'counted through the songs');
      final tracks = await repo.watchPlaylistTracks(pl.id).first;
      expect([for (final t in tracks) t.position], [0, 2], reason: 'the stored positions, gap included');

      // Drag "c" (visible row 1) above "a" (visible row 0).
      await repo.reorderPlaylist(pl.id, tracks[1].position, tracks[0].position);
      expect(ids(await repo.watchPlaylistSongs(pl.id).first), ['c', 'a']);

      // Remove "a" by its real position (it used to pass the visible index).
      final after = await repo.watchPlaylistTracks(pl.id).first;
      final a = after.singleWhere((t) => t.item.id == 'a');
      await repo.removeSongFromPlaylist(pl.id, 'a', a.position);
      expect(ids(await repo.watchPlaylistSongs(pl.id).first), ['c']);
    });

    test('a song is not added twice unless asked; a batch skips what is there', () async {
      for (final id in ['a', 'b', 'c']) {
        await insertRow(id, title: id);
      }
      final pl = await repo.createPlaylist('Mix');
      expect(await repo.addSongToPlaylist(pl.id, 'a'), isTrue);
      expect(await repo.addSongToPlaylist(pl.id, 'a'), isFalse, reason: 'duplicate guard');
      expect(await repo.addSongToPlaylist(pl.id, 'a', allowDuplicate: true), isTrue);
      expect(await repo.addSongsToPlaylist(pl.id, ['a', 'b', 'b', 'c']), 2);
      expect(ids(await repo.watchPlaylistSongs(pl.id).first), ['a', 'a', 'b', 'c']);
      expect(await repo.watchPlaylistIdsContaining('b').first, {pl.id});
      expect(await repo.watchPlaylistIdsContaining('zzz').first, isEmpty);
    });

    test('Undo puts a removed song back in its place', () async {
      for (final id in ['a', 'b', 'c']) {
        await insertRow(id, title: id);
      }
      final pl = await repo.createPlaylist('Mix');
      await repo.addSongsToPlaylist(pl.id, ['a', 'b', 'c']);
      await repo.removeSongFromPlaylist(pl.id, 'b', 1);
      await repo.insertSongIntoPlaylist(pl.id, 'b', 1);
      final tracks = await repo.watchPlaylistTracks(pl.id).first;
      expect([for (final t in tracks) (t.item.id, t.position)], [('a', 0), ('b', 1), ('c', 2)]);
    });

    test('ids never collide, even within one millisecond', () async {
      final repo2 = LibraryRepositoryImpl(db, store, Random(1));
      final made = <String>{};
      for (var i = 0; i < 40; i++) {
        made.add((await repo2.createPlaylist('P$i')).id);
      }
      expect(made, hasLength(40));
      expect(made.first, matches(RegExp(r'^pl_\d+_[0-9a-f]{12}$')));
    });

    test('a rename is seen live, and a deleted playlist reads null', () async {
      final pl = await repo.createPlaylist('Old');
      final names = <String?>[];
      final sub = repo.watchPlaylist(pl.id).listen((p) => names.add(p?.name));
      await pumpEventQueue();
      await repo.renamePlaylist(pl.id, 'New');
      await pumpEventQueue();
      await repo.deletePlaylist(pl.id);
      await pumpEventQueue();
      await sub.cancel();
      expect(names, ['Old', 'New', null]);
    });

    test('names sort without regard to case; covers are the first four different songs', () async {
      await repo.createPlaylist('beta');
      final alpha = await repo.createPlaylist('Alpha');
      await repo.createPlaylist('Gamma');
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        await insertRow(id, title: id);
      }
      await repo.addSongsToPlaylist(alpha.id, ['a', 'b', 'c', 'd', 'e']);
      final playlists = await repo.watchPlaylists().first;
      expect(playlists.map((p) => p.name), ['Alpha', 'beta', 'Gamma']);
      expect(ids(playlists.first.coverSongs), ['a', 'b', 'c', 'd']);
    });
  });

  group('missing files and online items (LIB-07, LIB-12)', () {
    setUp(() async {
      await insertRow('here', title: 'Here', album: 'X');
      await insertRow('gone', title: 'Gone', album: 'X', availability: 'missing', favorite: true);
      await insertRow('yt_dQw4w9WgXcQ', title: 'Online', source: 'online', favorite: true);
    });

    test('a missing file and an online item stay out of songs, albums, artists and Home', () async {
      expect(ids(await repo.watchMediaItems(mediaType: MediaType.audio).first), ['here']);
      expect((await repo.watchAlbums().first).single.songCount, 1);
      expect((await repo.watchArtists().first).single.songCount, 1);
      expect(await repo.watchRecentlyAdded().first, hasLength(1));
    });

    test('Favourites shows a liked online item, not a missing file', () async {
      expect(ids(await repo.watchFavorites().first), ['yt_dQw4w9WgXcQ']);
    });

    test('saving an online item again keeps its like and plays, and refreshes its title', () async {
      final saved = await repo.saveOnlineItem(MediaItem(
        id: 'yt_dQw4w9WgXcQ',
        uri: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        mediaType: MediaType.audio,
        title: 'Online (new title)',
        durationMs: 0,
        sizeBytes: 0,
        dateAdded: DateTime(2026),
        source: 'online',
        artworkPath: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      ));
      expect(saved.isFavorite, isTrue);
      expect(saved.title, 'Online (new title)');
      expect(saved.artworkPath, startsWith('https://'));
      expect(
        () => repo.saveOnlineItem(saved.copyWith(uri: 'content://media/1')),
        throwsArgumentError,
        reason: 'only an https watch link is saved as an online item',
      );
    });

    test('a playlist counts only the songs that are there', () async {
      final pl = await repo.createPlaylist('Mix');
      await repo.addSongsToPlaylist(pl.id, ['here', 'gone', 'yt_dQw4w9WgXcQ']);
      expect((await repo.watchPlaylists().first).single.songCount, 2);
      expect(ids(await repo.watchPlaylistSongs(pl.id).first), ['here', 'yt_dQw4w9WgXcQ']);
    });
  });

  group('liked songs (LIB-13)', () {
    test('liking stamps the time; Favourites is newest first; unliking clears it', () async {
      await insertRow('a', title: 'Zed');
      await insertRow('b', title: 'Abe');
      await repo.toggleFavorite('a');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await repo.toggleFavorite('b');
      expect(ids(await repo.watchFavorites().first), ['b', 'a'], reason: 'newest liked first, not A-Z');
      await repo.toggleFavorite('b');
      final b = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('b'))).getSingle();
      expect(b.favoritedAt, isNull);
      expect(ids(await repo.watchFavorites().first), ['a']);
    });
  });

  group('scan bookkeeping (LIB-11, LIB-15)', () {
    test('a rescan keeps the first date a file was seen and refreshes its tags', () async {
      store.audio = [_track('1', 'Old title', dateAdded: 1600000000)];
      await repo.scanDeviceMedia();
      store.audio = [_track('1', 'New title', dateAdded: 1700000000, album: 'Tagged')];
      await repo.scanDeviceMedia();
      final row = await db.select(db.mediaItemsTable).getSingle();
      expect(row.dateAdded, DateTime.fromMillisecondsSinceEpoch(1600000000 * 1000));
      expect(row.title, 'New title');
      expect(row.album, 'Tagged');
      expect(row.searchKey, contains('tagged'));
    });

    test('counts the songs new to the library, not a file that came back under a new id', () async {
      store.audio = [_track('1', 'One', size: 111), _track('2', 'Two', size: 222)];
      await repo.scanDeviceMedia();
      expect(repo.lastScanNewSongCount, 2);
      store.audio = [_track('1', 'One', size: 111), _track('2', 'Two', size: 222), _track('3', 'Three', size: 333)];
      await repo.scanDeviceMedia();
      expect(repo.lastScanNewSongCount, 1);
      // "Two" moves to id 20 (restored phone): carried over, not new.
      store.audio = [_track('1', 'One', size: 111), _track('20', 'Two', size: 222), _track('3', 'Three', size: 333)];
      await repo.scanDeviceMedia();
      expect(repo.lastScanNewSongCount, 0);
    });

    test('asks the phone for its media generation', () async {
      store.generation = 'external_primary:42';
      expect(await repo.mediaStoreGeneration(), 'external_primary:42');
    });
  });

  group('song orders (LIB-14)', () {
    test('album order is album, then track; most played is the most played first', () async {
      store.audio = [
        _track('1', 'Second', album: 'B side', albumId: '1', track: 2),
        _track('2', 'First', album: 'B side', albumId: '1', track: 1),
        _track('3', 'Only', album: 'A side', albumId: '2', track: 1),
      ];
      await repo.scanDeviceMedia();
      final byAlbum = await repo.watchSongs(sortBy: SongSortOption.album).first;
      expect([for (final s in byAlbum) s.title], ['Only', 'First', 'Second']);
      await repo.recordPlay('audio_1');
      await repo.recordPlay('audio_1');
      await repo.recordPlay('audio_3');
      final played = await repo.watchSongs(sortBy: SongSortOption.mostPlayed, ascending: false).first;
      expect([for (final s in played) s.title], ['Second', 'Only', 'First']);
    });
  });
}
