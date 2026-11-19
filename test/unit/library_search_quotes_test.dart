// Library search and the iPhone keyboard (iOS parity P3, task 1): the
// iPhone types curly quotes (’ “ ”) and long dashes, titles from the web
// often have them, and people type either. Both what is stored and what is
// typed fold to the plain ' " and -, and keys made before this rule are
// rebuilt (the version tag at the end of the key changed).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/data/database/search_text.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playlist_and_groups.dart';

void main() {
  group('folding quotes and dashes', () {
    test('curly and other typographic quotes fold to the plain ones', () {
      expect(foldForSearch('Don’t Stop'), "don't stop");
      expect(foldForSearch('‘Til I Die'), "'til i die");
      expect(foldForSearch('rock ʼn roll'), "rock 'n roll");
      expect(foldForSearch('Don´t'), "don't", reason: 'an acute accent typed for an apostrophe');
      expect(foldForSearch('Don`t'), "don't");
      expect(foldForSearch('‛x′'), "'x'");
      expect(foldForSearch('“Hello”'), '"hello"');
      expect(foldForSearch('„Hallo‟'), '"hallo"');
      expect(foldForSearch('«Bonjour»'), '"bonjour"');
      expect(foldForSearch('12″'), '12"');
      expect(foldForSearch('＇＂'), '\'"', reason: 'fullwidth forms');
    });

    test('typographic dashes fold to a plain hyphen', () {
      expect(foldForSearch('Artist – Title'), 'artist - title');
      expect(foldForSearch('Artist — Title'), 'artist - title');
      expect(foldForSearch('A‐B‑C‒D―E−F'), 'a-b-c-d-e-f');
    });

    test('what is typed folds the same way, so either spelling finds the other', () {
      expect(searchTerms('don’t'), ["don't"]);
      expect(searchTerms('“live”'), ['"live"']);
      expect(matchesAllTerms(searchTerms("don't"), [foldForSearch('Don’t Stop')]), isTrue);
      expect(matchesAllTerms(searchTerms('don’t'), [foldForSearch("Don't Stop")]), isTrue);
      expect(matchesAllTerms(searchTerms('a - b'), [foldForSearch('A – B')]), isTrue);
    });

    test('Devanagari, accents and the romanised search are unchanged', () {
      expect(foldForSearch('Beyoncé'), 'beyonce');
      expect(foldForSearch('नेपाली गीत'), 'नेपाली गीत');
      expect(matchesAllTerms(['resham'], [foldForSearch('रेशम फिरिरी')]), isTrue);
    });

    test('keys carry the new version tag', () {
      expect(searchKeyVersionTag, '', reason: 'bumped from U+E003 for the quote folding');
      expect(isCurrentSearchKey(librarySearchKey(title: 'x')), isTrue);
      expect(isCurrentSearchKey('x\n\n'), isFalse, reason: 'a key from the previous rules is rebuilt');
      expect(librarySearchKey(title: 'Don’t Stop', artist: 'Band'), contains("don't stop"));
    });
  });

  group('searching the library', () {
    late AppDatabase db;
    late LibraryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepositoryImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insert(String id, String title, {String? artist, String? searchKey, bool withKey = true}) {
      return db.into(db.mediaItemsTable).insert(
            MediaItemsTableCompanion.insert(
              id: id,
              uri: '/downloads/$id.m4a',
              mediaType: 'audio',
              title: title,
              artist: Value(artist),
              durationMs: 1000,
              sizeBytes: 1,
              dateAdded: DateTime(2026),
              source: const Value('download'),
              searchKey: Value(searchKey ?? (withKey ? librarySearchKey(title: title, artist: artist) : null)),
            ),
          );
    }

    Future<List<String>> search(String query) async => [
          for (final item in await repo.watchMediaItems(mediaType: MediaType.audio, searchQuery: query).first) item.id,
        ];

    test("\"don't\" finds \"Don’t\" and \"don’t\" finds \"Don't\"", () async {
      await insert('curly', 'Don’t Stop Me Now', artist: 'Queen');
      await insert('plain', "Don't Look Back", artist: 'Oasis');
      await insert('other', 'Dont Panic', artist: 'Coldplay');
      expect(await search("don't"), unorderedEquals(['curly', 'plain']));
      expect(await search('don’t'), unorderedEquals(['curly', 'plain']), reason: 'as the iPhone keyboard types it');
      expect(await search('“don’t stop”'), isEmpty, reason: 'quotes are matched, not dropped');
    });

    test('a title with a long dash is found with a plain hyphen', () async {
      await insert('dash', 'Sajjan Raj Vaidya — Hataarindai');
      expect(await search('vaidya - hataarindai'), ['dash']);
    });

    test('a key stored by the previous rules is rebuilt before the search', () async {
      // As the previous build stored it: the curly quote kept, tag U+E003.
      await insert('old', 'Don’t Stop', searchKey: 'don’t stop\n\n');
      expect(await search("don't"), ['old']);
      final row = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals('old'))).getSingle();
      expect(isCurrentSearchKey(row.searchKey), isTrue);
      expect(row.searchKey, startsWith("don't stop"));
    });

    test('playlists, albums and artists fold the same way', () async {
      await insert('a1', 'Song', artist: 'Guns N’ Roses');
      final artists = await repo.watchArtists(searchQuery: "guns n' roses").first;
      expect(artists.map((ArtistGroup a) => a.artist), ['Guns N’ Roses']);
    });
  });
}
