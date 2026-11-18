import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/media_permission_service.dart';
import '../../core/services/artwork_service.dart';
import '../../core/storage/settings_store.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/library_repository.dart';

final mediaPermissionServiceProvider = Provider<MediaPermissionService>((ref) {
  return MediaPermissionServiceImpl();
});

final audioPermissionStateProvider = NotifierProvider<AudioPermissionNotifier, MediaPermissionState>(() {
  return AudioPermissionNotifier();
});

final videoPermissionStateProvider = NotifierProvider<VideoPermissionNotifier, MediaPermissionState>(() {
  return VideoPermissionNotifier();
});

/// "mediaChanged" from the native MediaStore observer: songs or videos were
/// added, changed or removed on the phone (sent 2 s after the last change).
final mediaStoreChangesProvider = Provider<Stream<void>>((ref) {
  final controller = StreamController<void>.broadcast();
  const channel = MethodChannel('mediahub/media_store_events');
  try {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'mediaChanged' && !controller.isClosed) controller.add(null);
      return null;
    });
  } catch (_) {
    // No platform bindings (a plain unit test): no events.
  }
  ref.onDispose(() {
    try {
      channel.setMethodCallHandler(null);
    } catch (_) {}
    controller.close();
  });
  return controller.stream;
});

class AudioPermissionNotifier extends Notifier<MediaPermissionState> with WidgetsBindingObserver {
  @override
  MediaPermissionState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    Future.microtask(() => checkPermission());
    return MediaPermissionState.checking;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkPermission();
    }
  }

  Future<void> checkPermission() async {
    final service = ref.read(mediaPermissionServiceProvider);
    final result = await service.checkAudioPermission();
    // Gone meanwhile (the app or a test tore the providers down).
    if (!ref.mounted) return;
    state = result;
  }

  void updateState(MediaPermissionState newState) {
    state = newState;
  }
}

class VideoPermissionNotifier extends Notifier<MediaPermissionState> with WidgetsBindingObserver {
  @override
  MediaPermissionState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    Future.microtask(() => checkPermission());
    return MediaPermissionState.checking;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkPermission();
    }
  }

  Future<void> checkPermission() async {
    final service = ref.read(mediaPermissionServiceProvider);
    final result = await service.checkVideoPermission();
    // Gone meanwhile (the app or a test tore the providers down).
    if (!ref.mounted) return;
    state = result;
  }

  void updateState(MediaPermissionState newState) {
    state = newState;
  }
}

enum LibraryStatus { initial, loading, success, error }

/// What the last manual refresh found, shown once as a snackbar.
class ScanReport {
  /// Songs new to the library; null when the scan could not tell.
  final int? newSongs;

  /// Tells two reports with the same count apart.
  final int serial;

  const ScanReport({required this.newSongs, required this.serial});

  String get message => switch (newSongs) {
        null => 'Library refreshed',
        0 => 'No new songs',
        1 => '1 new song',
        final n => '$n new songs',
      };
}

class LibraryState {
  final MediaPermissionState permissionState;
  final LibraryStatus status;
  final List<MediaItem> items;
  final String searchQuery;
  final MediaSortOption sortBy;
  final bool ascending;
  final bool isScanning;
  final String? errorMessage;

  /// The Music tab's order ([sortBy] is its shared part; the Videos tab only
  /// uses that).
  final SongSortOption songSort;

  /// The last manual refresh's result, or null.
  final ScanReport? scanReport;

  const LibraryState({
    required this.permissionState,
    required this.status,
    required this.items,
    this.searchQuery = '',
    this.sortBy = MediaSortOption.title,
    this.ascending = true,
    this.isScanning = false,
    this.errorMessage,
    this.songSort = SongSortOption.title,
    this.scanReport,
  });

  /// [errorMessage] is kept unless a new one is given or [clearError] is set
  /// (before, any change dropped it, so a failed scan never showed).
  LibraryState copyWith({
    MediaPermissionState? permissionState,
    LibraryStatus? status,
    List<MediaItem>? items,
    String? searchQuery,
    MediaSortOption? sortBy,
    bool? ascending,
    bool? isScanning,
    String? errorMessage,
    bool clearError = false,
    SongSortOption? songSort,
    ScanReport? scanReport,
  }) {
    return LibraryState(
      permissionState: permissionState ?? this.permissionState,
      status: status ?? this.status,
      items: items ?? this.items,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      isScanning: isScanning ?? this.isScanning,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      songSort: songSort ?? this.songSort,
      scanReport: scanReport ?? this.scanReport,
    );
  }
}

/// One library rescan at a time per repository, shared by the Music and
/// Videos tabs (one scan reads both). Quiet rescans asked for while one runs
/// are folded into one more run after it.
class _ScanCoordinator {
  Future<void>? _running;
  bool _again = false;

  /// When the last scan finished.
  DateTime? lastScanAt;

  /// The phone's media generation at that scan, when it has one.
  String? lastGeneration;

  /// A scan is running now.
  bool get isRunning => _running != null;

  /// A resume check is asking the phone whether anything changed.
  bool checking = false;

  Future<void> quietScan(LibraryRepository repo) {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final future = _loop(repo);
    _running = future;
    return future;
  }

  Future<void> _loop(LibraryRepository repo) async {
    try {
      do {
        _again = false;
        await _scanOnce(repo);
      } while (_again);
    } finally {
      _running = null;
    }
  }

  Future<void> _scanOnce(LibraryRepository repo) async {
    String? generation;
    try {
      generation = await repo.mediaStoreGeneration();
    } catch (_) {}
    try {
      await repo.scanDeviceMedia();
      lastGeneration = generation;
    } catch (e) {
      debugPrint('[LibraryNotifier] quiet rescan failed: $e');
    }
    lastScanAt = DateTime.now();
    scanFinished();
  }

  /// A scan of any kind ended: a song may have gained a cover since.
  static void scanFinished() {
    try {
      ArtworkService.instance.clearNegativeCache();
    } catch (_) {}
  }
}

abstract class BaseLibraryNotifier extends Notifier<LibraryState> with WidgetsBindingObserver {
  MediaType get mediaType;
  StreamSubscription<List<MediaItem>>? _subscription;
  StreamSubscription<void>? _changesSubscription;

  /// A rescan on resume waits this long after the last one.
  static const Duration resumeRescanAfter = Duration(seconds: 60);

  /// Repositories that already had their automatic "once per app start" rescan.
  /// Keyed by repository instance so the Music and Videos tabs share one scan
  /// (one scan reads both audio and video) and tests with fresh repos start clean.
  static final Expando<bool> _autoScannedRepos = Expando<bool>('libraryAutoScan');
  static final Expando<_ScanCoordinator> _coordinators = Expando<_ScanCoordinator>('libraryScans');

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);
  MediaPermissionService get _permissionService => ref.read(mediaPermissionServiceProvider);

  _ScanCoordinator _coordinatorFor(LibraryRepository repo) => _coordinators[repo] ??= _ScanCoordinator();

  String get _settingsPrefix => 'library.${mediaType.name}';

  bool get _hasAccess =>
      state.permissionState == MediaPermissionState.granted || state.permissionState == MediaPermissionState.limited;

  @override
  LibraryState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _subscription?.cancel();
      _subscription = null;
      _changesSubscription?.cancel();
      _changesSubscription = null;
    });

    final permState = mediaType == MediaType.audio
        ? ref.watch(audioPermissionStateProvider)
        : ref.watch(videoPermissionStateProvider);

    Future.microtask(() => _handlePermissionChange(permState));

    final (songSort, ascending) = _savedSort();
    return LibraryState(
      permissionState: permState,
      status: (permState == MediaPermissionState.granted || permState == MediaPermissionState.limited)
          ? LibraryStatus.loading
          : (permState == MediaPermissionState.checking ? LibraryStatus.initial : LibraryStatus.success),
      items: const [],
      songSort: songSort,
      sortBy: songSort.mediaSort ?? MediaSortOption.title,
      ascending: ascending,
    );
  }

  /// The order picked last time (Settings), title A-Z the first time.
  (SongSortOption, bool) _savedSort() {
    try {
      final store = SettingsStore.instance;
      final name = store.getString('$_settingsPrefix.sort');
      var sort = SongSortOption.values.where((s) => s.name == name).firstOrNull ?? SongSortOption.title;
      // Videos only offer the shared orders.
      if (mediaType == MediaType.video && sort.mediaSort == null) sort = SongSortOption.title;
      final ascending = store.getBool('$_settingsPrefix.ascending', defaultValue: !sort.startsDescending);
      return (sort, ascending);
    } catch (_) {
      return (SongSortOption.title, true);
    }
  }

  void _saveSort() {
    try {
      final store = SettingsStore.instance;
      unawaited(store.setString('$_settingsPrefix.sort', state.songSort.name));
      unawaited(store.setBool('$_settingsPrefix.ascending', state.ascending));
    } catch (_) {}
  }

  void _handlePermissionChange(MediaPermissionState permState) {
    state = state.copyWith(permissionState: permState);
    if (permState == MediaPermissionState.granted || permState == MediaPermissionState.limited) {
      if (_subscription == null) {
        state = state.copyWith(status: LibraryStatus.loading);
        _subscribeToMediaItems();
      }
      _listenForMediaChanges();
      _autoScanOnce();
    }
  }

  /// New songs and videos on the phone show up by themselves: the native
  /// MediaStore observer reports a change and the library rescans quietly.
  void _listenForMediaChanges() {
    if (_changesSubscription != null) return;
    try {
      _changesSubscription = ref.read(mediaStoreChangesProvider).listen((_) => _quietRescan());
    } catch (_) {}
  }

  void _quietRescan() {
    if (!_hasAccess) return;
    final LibraryRepository repo;
    try {
      repo = _repository;
    } catch (_) {
      return;
    }
    unawaited(_coordinatorFor(repo).quietScan(repo));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(rescanIfStale());
  }

  /// Back in the app: rescan when the last scan is over a minute old, unless
  /// the phone says nothing changed (Android 11+).
  @visibleForTesting
  Future<void> rescanIfStale({DateTime? now}) async {
    if (!_hasAccess) return;
    final LibraryRepository repo;
    try {
      repo = _repository;
    } catch (_) {
      return;
    }
    final coordinator = _coordinatorFor(repo);
    // The Music and Videos tabs both come back: one check is enough.
    if (coordinator.isRunning || coordinator.checking) return;
    final last = coordinator.lastScanAt;
    final at = now ?? DateTime.now();
    if (last != null && at.difference(last) < resumeRescanAfter) return;
    coordinator.checking = true;
    try {
      if (last != null && coordinator.lastGeneration != null) {
        String? generation;
        try {
          generation = await repo.mediaStoreGeneration();
        } catch (_) {}
        if (generation != null && generation == coordinator.lastGeneration) return;
      }
      await coordinator.quietScan(repo);
    } finally {
      coordinator.checking = false;
    }
  }

  /// Songs and videos added to the phone since the last visit (or downloaded by
  /// another app) appear without tapping refresh: one quiet rescan per app start.
  /// The list updates by itself because it streams from the database. A failure
  /// here is only logged; the manual refresh button still reports errors.
  void _autoScanOnce() {
    final LibraryRepository repo;
    try {
      repo = _repository;
    } catch (_) {
      return;
    }
    if (_autoScannedRepos[repo] == true) return;
    _autoScannedRepos[repo] = true;
    unawaited(() async {
      try {
        await _coordinatorFor(repo).quietScan(repo);
      } catch (e) {
        debugPrint('[LibraryNotifier] automatic rescan failed: $e');
      }
    }());
  }

  Future<void> checkPermissionAndInit() async {
    final permState = mediaType == MediaType.audio
        ? await _permissionService.checkAudioPermission()
        : await _permissionService.checkVideoPermission();

    if (mediaType == MediaType.audio) {
      ref.read(audioPermissionStateProvider.notifier).updateState(permState);
    } else {
      ref.read(videoPermissionStateProvider.notifier).updateState(permState);
    }

    if (permState == MediaPermissionState.granted || permState == MediaPermissionState.limited) {
      state = state.copyWith(
        permissionState: permState,
        status: LibraryStatus.loading,
      );
      _subscribeToMediaItems();
    } else {
      state = state.copyWith(
        permissionState: permState,
        status: LibraryStatus.success,
      );
    }
  }

  Future<void> requestPermission() async {
    try {
      final newState = mediaType == MediaType.audio
          ? await _permissionService.requestAudioPermission()
          : await _permissionService.requestVideoPermission();

      if (mediaType == MediaType.audio) {
        ref.read(audioPermissionStateProvider.notifier).updateState(newState);
      } else {
        ref.read(videoPermissionStateProvider.notifier).updateState(newState);
      }

      debugPrint('[LibraryNotifier] Permission request result: $newState');
      state = state.copyWith(permissionState: newState, clearError: true);

      if (newState == MediaPermissionState.granted || newState == MediaPermissionState.limited) {
        state = state.copyWith(status: LibraryStatus.loading);
        await scanDevice();
        _subscribeToMediaItems();
      }
    } catch (e, stack) {
      debugPrint('[LibraryNotifier] Error in requestPermission: $e\n$stack');
      state = state.copyWith(
        status: LibraryStatus.error,
        errorMessage: "Couldn't ask for access. Try again, or allow it in Settings.",
      );
    }
  }

  Future<void> openSettings() async {
    try {
      await _permissionService.openSettings();
    } catch (e) {
      debugPrint('[LibraryNotifier] Error opening settings: $e');
    }
  }

  /// The refresh button: scans now, reports failures, and says how many new
  /// songs it found ([LibraryState.scanReport]).
  Future<void> scanDevice() async {
    if (!_hasAccess) {
      debugPrint('[LibraryNotifier] scanDevice skipped: permission is not granted (${state.permissionState})');
      return;
    }

    state = state.copyWith(isScanning: true, clearError: true);
    final repo = _repository;
    String? generation;
    try {
      generation = await repo.mediaStoreGeneration();
    } catch (_) {}
    try {
      debugPrint('[LibraryNotifier] Starting scanDeviceMedia()...');
      await repo.scanDeviceMedia();
      debugPrint('[LibraryNotifier] scanDeviceMedia() finished successfully.');
      final coordinator = _coordinatorFor(repo);
      coordinator.lastScanAt = DateTime.now();
      coordinator.lastGeneration = generation;
      int? newSongs;
      try {
        newSongs = repo.lastScanNewSongCount;
      } catch (_) {}
      state = state.copyWith(
        scanReport: ScanReport(newSongs: newSongs, serial: (state.scanReport?.serial ?? 0) + 1),
      );
    } catch (e, stack) {
      debugPrint('[LibraryNotifier] scanDevice failed: $e\n$stack');
      state = state.copyWith(
        status: state.items.isEmpty ? LibraryStatus.error : null,
        errorMessage: "Couldn't refresh your library. Try again in a moment.",
      );
    } finally {
      state = state.copyWith(isScanning: false);
      _ScanCoordinator.scanFinished();
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _subscribeToMediaItems();
  }

  /// Picks an order; picking the current one again flips its direction.
  /// Date added and duration start newest / longest first.
  void setSortOption(MediaSortOption sortBy) {
    setSongSort(switch (sortBy) {
      MediaSortOption.title => SongSortOption.title,
      MediaSortOption.artist => SongSortOption.artist,
      MediaSortOption.dateAdded => SongSortOption.dateAdded,
      MediaSortOption.duration => SongSortOption.duration,
    });
  }

  /// [setSortOption] with the song-only orders too (album, most played).
  void setSongSort(SongSortOption sort) {
    if (mediaType == MediaType.video && sort.mediaSort == null) return;
    final isSameOption = state.songSort == sort;
    state = state.copyWith(
      songSort: sort,
      sortBy: sort.mediaSort ?? MediaSortOption.title,
      ascending: isSameOption ? !state.ascending : !sort.startsDescending,
    );
    _saveSort();
    _subscribeToMediaItems();
  }

  /// Retry after the list failed to load.
  void retry() {
    state = state.copyWith(status: LibraryStatus.loading, clearError: true);
    _subscribeToMediaItems();
  }

  Stream<List<MediaItem>> _itemsStream() {
    final shared = state.songSort.mediaSort;
    if (shared != null || mediaType == MediaType.video) {
      return _repository.watchMediaItems(
        mediaType: mediaType,
        searchQuery: state.searchQuery,
        sortBy: shared ?? MediaSortOption.title,
        ascending: state.ascending,
      );
    }
    return _repository.watchSongs(
      searchQuery: state.searchQuery,
      sortBy: state.songSort,
      ascending: state.ascending,
    );
  }

  void _subscribeToMediaItems() {
    _subscription?.cancel();
    _subscription = _itemsStream().listen(
      (items) {
        state = state.copyWith(
          status: LibraryStatus.success,
          items: items,
          // The list is back after a failure: its message goes.
          clearError: state.status == LibraryStatus.error,
        );
      },
      onError: (Object err) {
        debugPrint('[LibraryNotifier] list failed: $err');
        state = state.copyWith(
          status: LibraryStatus.error,
          errorMessage: "Couldn't load your library.",
        );
      },
    );
  }
}

class MusicLibraryNotifier extends BaseLibraryNotifier {
  @override
  MediaType get mediaType => MediaType.audio;
}

class VideoLibraryNotifier extends BaseLibraryNotifier {
  @override
  MediaType get mediaType => MediaType.video;
}

final musicLibraryProvider =
    NotifierProvider<MusicLibraryNotifier, LibraryState>(
        MusicLibraryNotifier.new);

final videoLibraryProvider =
    NotifierProvider<VideoLibraryNotifier, LibraryState>(
        VideoLibraryNotifier.new);
