// The resume rescan on iPhone (iOS parity P3, task 3): there is no phone
// library to read, so coming back to the app must not run an empty scan
// (which also forgot which songs have no cover). The scan on open still
// runs once (it gives new downloads their search keys). Android is unchanged.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
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

class _Repo implements LibraryRepository {
  int scans = 0;

  @override
  Future<void> scanDeviceMedia() async => scans++;

  @override
  int? get lastScanNewSongCount => null;

  @override
  Future<String?> mediaStoreGeneration() async => null;

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) =>
      Stream.value(const []);

  @override
  Stream<List<MediaItem>> watchSongs({
    String? searchQuery,
    SongSortOption sortBy = SongSortOption.title,
    bool ascending = true,
  }) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
    await SettingsStore.instance.setString('library.audio.sort', 'title');
    await SettingsStore.instance.setBool('library.audio.ascending', true);
  });

  tearDown(() {
    container.dispose();
    PlatformInfo.resetForTests();
  });

  Future<void> start() async {
    container.listen(musicLibraryProvider, (_, _) {}, fireImmediately: true);
    container.listen(videoLibraryProvider, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 10; i++) {
      await pumpEventQueue();
    }
  }

  test('iPhone: coming back to the app does not rescan, and keeps the "no cover" answers', () async {
    PlatformInfo.debugIsIOS = true;
    await start();
    expect(repo.scans, 1, reason: 'the scan on open still runs once');
    final generation = ArtworkService.instance.negativeGeneration;

    final later = DateTime.now().add(const Duration(minutes: 5));
    await container.read(musicLibraryProvider.notifier).rescanIfStale(now: later);
    await container.read(videoLibraryProvider.notifier).rescanIfStale(now: later);
    expect(repo.scans, 1, reason: 'nothing on the iPhone to scan');
    expect(ArtworkService.instance.negativeGeneration, generation, reason: 'no cover lookups asked again');
  });

  test('Android: coming back after a minute still rescans', () async {
    PlatformInfo.debugIsAndroid = true;
    await start();
    expect(repo.scans, 1);
    await container
        .read(musicLibraryProvider.notifier)
        .rescanIfStale(now: DateTime.now().add(const Duration(minutes: 5)));
    expect(repo.scans, 2);
  });
}
