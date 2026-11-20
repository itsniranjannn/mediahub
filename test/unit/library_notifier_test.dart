// The library notifier (fix plan P2, LIB-11 and LIB-14): new files show up
// by themselves (the native "mediaChanged" event and a rescan on resume that
// is skipped when nothing changed), a manual refresh says how many songs are
// new and keeps its error, and the order picked last time comes back with
// newest / longest first on the first pick.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/models/playlist_and_groups.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/library/library_notifier.dart';

class _Permissions implements MediaPermissionService {
  @override
  Future<MediaPermissionState> checkAudioPermission() async => MediaPermissionState.granted;
  @override
  Future<MediaPermissionState> checkVideoPermission() async => MediaPermissionState.granted;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts scans; the phone's media generation and scan result are settable.
class _Repo implements LibraryRepository {
  int scans = 0;
  String? generation = 'gen:1';
  int? newSongs = 0;
  Object? scanError;
  final List<String> streams = [];

  @override
  Future<void> scanDeviceMedia() async {
    scans++;
    final error = scanError;
    if (error != null) throw error;
  }

  @override
  int? get lastScanNewSongCount => newSongs;

  @override
  Future<String?> mediaStoreGeneration() async => generation;

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) {
    streams.add('media:${sortBy.name}:$ascending');
    return Stream.value(const []);
  }

  @override
  Stream<List<MediaItem>> watchSongs({
    String? searchQuery,
    SongSortOption sortBy = SongSortOption.title,
    bool ascending = true,
  }) {
    streams.add('songs:${sortBy.name}:$ascending');
    return Stream.value(const []);
  }

  @override
  Stream<List<AlbumGroup>> watchAlbums({String? searchQuery}) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _events = MethodChannel('mediahub/media_store_events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Repo repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _Repo();
    container = ProviderContainer(overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      mediaPermissionServiceProvider.overrideWithValue(_Permissions()),
    ]);
    // Clean saved orders (the shared store is memory-only in tests).
    await SettingsStore.instance.setString('library.audio.sort', 'title');
    await SettingsStore.instance.setBool('library.audio.ascending', true);
  });

  tearDown(() => container.dispose());

  /// Starts the Music library and lets its permission check and first
  /// automatic scan finish.
  Future<void> start() async {
    container.listen(musicLibraryProvider, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
  }

  Future<void> sendMediaChanged() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      _events.name,
      _events.codec.encodeMethodCall(const MethodCall('mediaChanged')),
      (_) {},
    );
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
  }

  test('a MediaStore change rescans quietly (new songs show up without a refresh)', () async {
    await start();
    expect(repo.scans, 1, reason: 'the automatic scan on open');
    await sendMediaChanged();
    expect(repo.scans, 2);
    expect(container.read(musicLibraryProvider).scanReport, isNull, reason: 'quiet: no snackbar');
  });

  test('back in the app: rescans after a minute, unless the phone says nothing changed', () async {
    await start();
    final notifier = container.read(musicLibraryProvider.notifier);
    final later = DateTime.now().add(const Duration(minutes: 2));

    await notifier.rescanIfStale();
    expect(repo.scans, 1, reason: 'the last scan is under a minute old');

    await notifier.rescanIfStale(now: later);
    expect(repo.scans, 1, reason: 'same media generation: nothing to do');

    repo.generation = 'gen:2';
    await notifier.rescanIfStale(now: later);
    expect(repo.scans, 2, reason: 'the files changed');
  });

  test('the Music and Videos tabs coming back together rescan once', () async {
    container.listen(videoLibraryProvider, (_, _) {}, fireImmediately: true);
    await start();
    final later = DateTime.now().add(const Duration(minutes: 2));
    repo.generation = 'gen:9';
    await Future.wait([
      container.read(musicLibraryProvider.notifier).rescanIfStale(now: later),
      container.read(videoLibraryProvider.notifier).rescanIfStale(now: later),
    ]);
    expect(repo.scans, 2, reason: 'the one on open, then one for the resume');
  });

  test('a phone that cannot tell its generation rescans after a minute', () async {
    repo.generation = null;
    await start();
    await container
        .read(musicLibraryProvider.notifier)
        .rescanIfStale(now: DateTime.now().add(const Duration(minutes: 2)));
    expect(repo.scans, 2);
  });

  test('the refresh button reports how many songs are new', () async {
    await start();
    repo.newSongs = 12;
    await container.read(musicLibraryProvider.notifier).scanDevice();
    final report = container.read(musicLibraryProvider).scanReport;
    expect(report?.message, '12 new songs');
    repo.newSongs = 0;
    await container.read(musicLibraryProvider.notifier).scanDevice();
    final second = container.read(musicLibraryProvider).scanReport!;
    expect(second.message, 'No new songs');
    expect(second.serial, report!.serial + 1, reason: 'shown again even with the same text');
  });

  test('a failed refresh keeps its message (any later change used to wipe it)', () async {
    await start();
    repo.scanError = Exception('disk');
    await container.read(musicLibraryProvider.notifier).scanDevice();
    final state = container.read(musicLibraryProvider);
    expect(state.isScanning, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage, isNot(contains('disk')), reason: 'no raw exception text on screen');
  });

  test('Date added and Duration start newest / longest first; picking again flips', () async {
    await start();
    final notifier = container.read(musicLibraryProvider.notifier);

    notifier.setSongSort(SongSortOption.dateAdded);
    expect(container.read(musicLibraryProvider).ascending, isFalse);
    notifier.setSongSort(SongSortOption.dateAdded);
    expect(container.read(musicLibraryProvider).ascending, isTrue);

    notifier.setSortOption(MediaSortOption.duration);
    expect(container.read(musicLibraryProvider).ascending, isFalse);

    notifier.setSongSort(SongSortOption.title);
    expect(container.read(musicLibraryProvider).ascending, isTrue);
  });

  test('album and most-played orders use the song query; the order is remembered', () async {
    await start();
    final notifier = container.read(musicLibraryProvider.notifier);
    notifier.setSongSort(SongSortOption.mostPlayed);
    await pumpEventQueue();
    expect(repo.streams.last, 'songs:mostPlayed:false');
    expect(SettingsStore.instance.getString('library.audio.sort'), 'mostPlayed');
    expect(SettingsStore.instance.getBool('library.audio.ascending', defaultValue: true), isFalse);

    // A new session reads it back.
    final next = ProviderContainer(overrides: [
      libraryRepositoryProvider.overrideWithValue(repo),
      mediaPermissionServiceProvider.overrideWithValue(_Permissions()),
    ]);
    addTearDown(next.dispose);
    final state = next.read(musicLibraryProvider);
    expect(state.songSort, SongSortOption.mostPlayed);
    expect(state.ascending, isFalse);
    await pumpEventQueue();
  });

  test('ScanReport words', () {
    expect(const ScanReport(newSongs: 1, serial: 1).message, '1 new song');
    expect(const ScanReport(newSongs: null, serial: 1).message, 'Library refreshed');
  });
}
