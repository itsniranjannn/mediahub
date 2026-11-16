import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/explore/explore_notifier.dart';
import 'package:mediahub/features/explore/online_models.dart';
import 'package:mediahub/features/explore/online_source.dart';

/// Key the notifier persists its history under (private in the notifier).
const String _historyKey = 'explore_history';

/// In-memory [OnlineSource]. By default every search answers immediately with
/// one result named after the query; [onSearch] replaces that behaviour.
class FakeOnlineSource implements OnlineSource {
  final List<String> queries = [];
  Future<List<OnlineVideo>> Function(String query)? onSearch;
  bool disposed = false;

  @override
  Future<List<OnlineVideo>> search(String query) {
    queries.add(query);
    final handler = onSearch;
    if (handler != null) return handler(query);
    return Future.value([video(query)]);
  }

  @override
  Future<OnlineStreams> streams(String videoId) async =>
      const OnlineStreams(audio: [], video: []);

  @override
  void dispose() => disposed = true;
}

OnlineVideo video(String title, {String id = 'dQw4w9WgXcQ'}) => OnlineVideo(
      id: id,
      title: title,
      author: 'Author of $title',
      thumbnailUrl: '',
      duration: const Duration(minutes: 3),
    );

OnlineStream audioStream(int? kbps, String container) => OnlineStream(
      url: 'https://rr1.googlevideo.com/a$kbps$container',
      kind: OnlineStreamKind.audio,
      label: '$kbps kbps',
      container: container,
      sizeBytes: 1000,
      bitrateKbps: kbps,
    );

OnlineStream videoStream(int? height) => OnlineStream(
      url: 'https://rr1.googlevideo.com/v$height',
      kind: OnlineStreamKind.video,
      label: '${height}p',
      container: 'mp4',
      sizeBytes: 1000,
      height: height,
    );

void main() {
  late FakeOnlineSource source;
  late ProviderContainer container;

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [onlineSourceProvider.overrideWithValue(source)],
    );
    addTearDown(c.dispose);
    return c;
  }

  ExploreNotifier notifier() => container.read(exploreProvider.notifier);
  ExploreState state() => container.read(exploreProvider);
  List<String> persisted() => SettingsStore.instance.getStringList(_historyKey);

  setUp(() async {
    // SettingsStore is never loaded in tests, so it is a process-wide in-memory map.
    await SettingsStore.instance.setStringList(_historyKey, const []);
    source = FakeOnlineSource();
    container = makeContainer();
  });

  group('ExploreNotifier initial state', () {
    test('starts empty and idle', () {
      final s = state();
      expect(s.query, '');
      expect(s.loading, isFalse);
      expect(s.hasSearched, isFalse);
      expect(s.results, isEmpty);
      expect(s.error, isNull);
      expect(s.history, isEmpty);
    });

    test('loads saved history from SettingsStore', () async {
      await SettingsStore.instance.setStringList(_historyKey, ['jazz', 'lofi']);
      final fresh = makeContainer();
      expect(fresh.read(exploreProvider).history, ['jazz', 'lofi']);
    });
  });

  group('search success', () {
    test('stores the results and remembers the query', () async {
      final results = [video('Lofi one'), video('Lofi two', id: 'aqz-KE-bpKQ')];
      source.onSearch = (_) async => results;

      await notifier().search('lofi');

      final s = state();
      expect(source.queries, ['lofi']);
      expect(s.query, 'lofi');
      expect(s.loading, isFalse);
      expect(s.hasSearched, isTrue);
      expect(s.error, isNull);
      expect(s.results, same(results));
      expect(s.history, ['lofi']);
      expect(persisted(), ['lofi']);
    });

    test('is loading while the request is in flight', () async {
      final pending = Completer<List<OnlineVideo>>();
      source.onSearch = (_) => pending.future;

      final future = notifier().search('jazz');
      expect(state().loading, isTrue);
      expect(state().hasSearched, isTrue);
      expect(state().query, 'jazz');
      expect(state().history, isEmpty, reason: 'only finished searches are remembered');

      pending.complete([video('Jazz')]);
      await future;
      expect(state().loading, isFalse);
      expect(state().results.single.title, 'Jazz');
    });

    test('history is most recent first', () async {
      await notifier().search('one');
      await notifier().search('two');
      await notifier().search('three');
      expect(state().history, ['three', 'two', 'one']);
      expect(persisted(), ['three', 'two', 'one']);
    });

    test('history dedupes case-insensitively and moves the repeat to the front', () async {
      await notifier().search('Lofi');
      await notifier().search('jazz');
      await notifier().search('LOFI');
      expect(state().history, ['LOFI', 'jazz']);
      expect(persisted(), ['LOFI', 'jazz']);
    });

    test('history keeps at most 8 entries', () async {
      for (var i = 1; i <= 10; i++) {
        await notifier().search('query $i');
      }
      final expected = [for (var i = 10; i >= 3; i--) 'query $i'];
      expect(state().history, expected);
      expect(state().history, hasLength(8));
      expect(persisted(), expected);
    });

    test('history survives a new notifier (persisted through SettingsStore)', () async {
      await notifier().search('first');
      await notifier().search('second');

      final fresh = makeContainer();
      expect(fresh.read(exploreProvider).history, ['second', 'first']);
      expect(fresh.read(exploreProvider).hasSearched, isFalse);
    });
  });

  group('query normalisation', () {
    test('empty and whitespace-only queries are ignored', () async {
      await notifier().search('');
      await notifier().search('   ');
      await notifier().search(' \n\t ');

      expect(source.queries, isEmpty);
      expect(state().hasSearched, isFalse);
      expect(state().loading, isFalse);
      expect(state().history, isEmpty);
    });

    test('query is trimmed before searching and remembering', () async {
      await notifier().search('  hello world \n');
      expect(source.queries, ['hello world']);
      expect(state().query, 'hello world');
      expect(state().history, ['hello world']);
    });

    test('query is capped at 120 characters', () async {
      await notifier().search('a' * 200);
      expect(source.queries.single, 'a' * 120);
      expect(state().query, hasLength(120));
      expect(state().history.single, hasLength(120));
    });

    test('a query of exactly 120 characters is kept whole', () async {
      final q = 'b' * 120;
      await notifier().search(q);
      expect(source.queries.single, q);
    });

    test('capping does not leave a trailing space behind', () async {
      await notifier().search('${'a' * 119} tail');
      expect(source.queries.single, 'a' * 119);
    });

    test('capping does not cut an emoji in half', () async {
      // The emoji's two UTF-16 units sit at index 119 and 120.
      await notifier().search('${'x' * 119}\u{1F600}more');
      final sent = source.queries.single;
      expect(sent, 'x' * 119);
      expect(sent.codeUnits.any((u) => u >= 0xD800 && u <= 0xDFFF), isFalse);
    });
  });

  group('search errors', () {
    test('an OnlineException shows its message and empty results', () async {
      source.onSearch = (_) async => throw const OnlineException('No internet connection.');

      await notifier().search('lofi');

      final s = state();
      expect(s.error, 'No internet connection.');
      expect(s.results, isEmpty);
      expect(s.loading, isFalse);
      expect(s.hasSearched, isTrue);
      expect(s.query, 'lofi', reason: 'kept so "Try again" can repeat it');
      expect(s.history, isEmpty, reason: 'failed searches are not remembered');
      expect(persisted(), isEmpty);
    });

    test('a failure clears results of an earlier successful search', () async {
      await notifier().search('ok');
      expect(state().results, isNotEmpty);

      source.onSearch = (_) async => throw const OnlineException('Search timed out.');
      await notifier().search('broken');

      expect(state().results, isEmpty);
      expect(state().error, 'Search timed out.');
      expect(state().history, ['ok']);
    });

    test('an unexpected exception shows a generic message', () async {
      source.onSearch = (_) async => throw StateError('boom');
      await notifier().search('lofi');
      expect(state().error, 'Something went wrong. Please try again.');
      expect(state().results, isEmpty);
      expect(state().loading, isFalse);
    });

    test('starting a new search clears the previous error', () async {
      source.onSearch = (_) async => throw const OnlineException('No internet connection.');
      await notifier().search('lofi');
      expect(state().error, isNotNull);

      final pending = Completer<List<OnlineVideo>>();
      source.onSearch = (_) => pending.future;
      final retry = notifier().search('lofi');
      expect(state().error, isNull);
      expect(state().loading, isTrue);

      pending.complete([video('Back online')]);
      await retry;
      expect(state().error, isNull);
      expect(state().results.single.title, 'Back online');
      expect(state().history, ['lofi']);
    });
  });

  group('race between searches', () {
    test('a slower older search never overwrites a newer one', () async {
      final slow = Completer<List<OnlineVideo>>();
      final fast = Completer<List<OnlineVideo>>();
      source.onSearch = (q) => q == 'old' ? slow.future : fast.future;

      final first = notifier().search('old');
      final second = notifier().search('new');

      fast.complete([video('New result')]);
      await second;
      expect(state().results.single.title, 'New result');
      expect(state().loading, isFalse);

      slow.complete([video('Old result')]);
      await first;
      final s = state();
      expect(s.query, 'new');
      expect(s.results.single.title, 'New result');
      expect(s.loading, isFalse);
      expect(s.history, ['new'], reason: 'the stale search is not remembered');
      expect(persisted(), ['new']);
    });

    test('an older search finishing first does not end the newer loading state', () async {
      final slow = Completer<List<OnlineVideo>>();
      final newer = Completer<List<OnlineVideo>>();
      source.onSearch = (q) => q == 'old' ? slow.future : newer.future;

      final first = notifier().search('old');
      final second = notifier().search('new');

      slow.complete([video('Old result')]);
      await first;
      expect(state().loading, isTrue, reason: 'still waiting for the newer search');
      expect(state().results, isEmpty);
      expect(state().query, 'new');

      newer.complete([video('New result')]);
      await second;
      expect(state().results.single.title, 'New result');
      expect(state().history, ['new']);
    });

    test('a stale failure does not replace newer results with an error', () async {
      final slow = Completer<List<OnlineVideo>>();
      source.onSearch = (q) => q == 'old' ? slow.future : Future.value([video('New result')]);

      final first = notifier().search('old');
      await notifier().search('new');

      slow.completeError(const OnlineException('Search timed out.'));
      await first;
      expect(state().error, isNull);
      expect(state().results.single.title, 'New result');
    });

    test('disposing while a search is in flight does not throw', () async {
      final pending = Completer<List<OnlineVideo>>();
      source.onSearch = (_) => pending.future;
      final c = ProviderContainer(
        overrides: [onlineSourceProvider.overrideWithValue(source)],
      );
      final future = c.read(exploreProvider.notifier).search('late');
      c.dispose();

      pending.complete([video('Too late')]);
      await expectLater(future, completes);
      expect(persisted(), isEmpty);
    });
  });

  group('history editing', () {
    setUp(() async {
      await SettingsStore.instance.setStringList(_historyKey, ['jazz', 'Lofi', 'rock']);
      container = makeContainer();
    });

    test('removeFromHistory removes only that entry and persists', () {
      notifier().removeFromHistory('Lofi');
      expect(state().history, ['jazz', 'rock']);
      expect(persisted(), ['jazz', 'rock']);
    });

    test('removeFromHistory of an unknown entry changes nothing', () {
      notifier().removeFromHistory('classical');
      expect(state().history, ['jazz', 'Lofi', 'rock']);
    });

    test('clearHistory empties the list and persists', () {
      notifier().clearHistory();
      expect(state().history, isEmpty);
      expect(persisted(), isEmpty);
      expect(makeContainer().read(exploreProvider).history, isEmpty);
    });

    test('editing history does not touch results', () async {
      await notifier().search('blues');
      notifier().removeFromHistory('jazz');
      expect(state().results.single.title, 'blues');
      expect(state().history, ['blues', 'Lofi', 'rock']);
    });
  });

  group('OnlineVideo.isValidId', () {
    test('accepts 11-character URL-safe ids', () {
      for (final id in ['dQw4w9WgXcQ', 'aqz-KE-bpKQ', 'abc_DEF-123', '___________', '-----------']) {
        expect(OnlineVideo.isValidId(id), isTrue, reason: id);
      }
    });

    test('rejects wrong lengths', () {
      for (final id in ['', 'a', 'dQw4w9WgXc', 'dQw4w9WgXcQQ', 'dQw4w9WgXcQdQw4w9WgXcQ']) {
        expect(OnlineVideo.isValidId(id), isFalse, reason: id);
      }
    });

    test('rejects URL and path injection attempts', () {
      const attempts = [
        'abc/../x',
        'abc/../xyz1', // 11 characters
        'a b',
        'dQw4w9WgXc ', // trailing space, 11 characters
        ' dQw4w9WgXc',
        'dQw4w9WgXc&', // query injection
        'dQw4w9WgX%2', // percent encoding
        '?v=dQw4w9Wg',
        'dQw4w9WgXc#',
        'dQw4w9WgXc.',
        'dQw4w9WgXcQ\n', // newline after a valid id
        'dQw4w9WgXcé', // non-ASCII letter
        'dQw4w9WgX\u{1F600}', // emoji (two UTF-16 units)
        'https://x.y',
      ];
      for (final id in attempts) {
        expect(OnlineVideo.isValidId(id), isFalse, reason: id);
      }
    });

    test('watchUrl embeds the id', () {
      expect(video('t').watchUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });
  });

  group('OnlineStreams', () {
    test('bestAudio is null without audio streams', () {
      expect(const OnlineStreams(audio: [], video: []).bestAudio, isNull);
    });

    test('bestAudio prefers the higher bitrate whatever the container', () {
      final streams = OnlineStreams(
        audio: [audioStream(128, 'mp4'), audioStream(160, 'webm'), audioStream(48, 'm4a')],
        video: const [],
      );
      expect(streams.bestAudio!.bitrateKbps, 160);
      expect(streams.bestAudio!.container, 'webm');
    });

    test('bestAudio prefers mp4/m4a on a bitrate tie, in any order', () {
      final webm = audioStream(128, 'webm');
      final mp4 = audioStream(128, 'mp4');
      final m4a = audioStream(128, 'm4a');
      expect(OnlineStreams(audio: [webm, mp4], video: const []).bestAudio, same(mp4));
      expect(OnlineStreams(audio: [mp4, webm], video: const []).bestAudio, same(mp4));
      expect(OnlineStreams(audio: [webm, m4a], video: const []).bestAudio, same(m4a));
    });

    test('bestAudio treats a missing bitrate as the lowest', () {
      final unknown = audioStream(null, 'm4a');
      final known = audioStream(64, 'webm');
      expect(OnlineStreams(audio: [unknown, known], video: const []).bestAudio, same(known));
      expect(OnlineStreams(audio: [unknown], video: const []).bestAudio, same(unknown));
    });

    test('bestAudio does not reorder the original list', () {
      final list = [audioStream(48, 'webm'), audioStream(160, 'm4a')];
      OnlineStreams(audio: list, video: const []).bestAudio;
      expect(list.first.bitrateKbps, 48);
    });

    test('bestVideo is null without video streams', () {
      expect(const OnlineStreams(audio: [], video: []).bestVideo, isNull);
    });

    test('bestVideo picks the highest height', () {
      final streams = OnlineStreams(
        audio: const [],
        video: [videoStream(360), videoStream(1080), videoStream(null), videoStream(720)],
      );
      expect(streams.bestVideo!.height, 1080);
      expect(streams.bestVideo!.label, '1080p');
    });

    test('bestVideo falls back to a stream without a known height', () {
      final only = videoStream(null);
      expect(OnlineStreams(audio: const [], video: [only]).bestVideo, same(only));
    });

    test('OnlineStream.isAudio follows the kind', () {
      expect(audioStream(128, 'm4a').isAudio, isTrue);
      expect(videoStream(720).isAudio, isFalse);
    });

    test('OnlineException.toString is the friendly message', () {
      expect(const OnlineException('No internet connection.').toString(), 'No internet connection.');
    });
  });
}
