import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/media_permission_service.dart';
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
    state = result;
  }

  void updateState(MediaPermissionState newState) {
    state = newState;
  }
}

enum LibraryStatus { initial, loading, success, error }

class LibraryState {
  final MediaPermissionState permissionState;
  final LibraryStatus status;
  final List<MediaItem> items;
  final String searchQuery;
  final MediaSortOption sortBy;
  final bool ascending;
  final bool isScanning;
  final String? errorMessage;

  const LibraryState({
    required this.permissionState,
    required this.status,
    required this.items,
    this.searchQuery = '',
    this.sortBy = MediaSortOption.title,
    this.ascending = true,
    this.isScanning = false,
    this.errorMessage,
  });

  LibraryState copyWith({
    MediaPermissionState? permissionState,
    LibraryStatus? status,
    List<MediaItem>? items,
    String? searchQuery,
    MediaSortOption? sortBy,
    bool? ascending,
    bool? isScanning,
    String? errorMessage,
  }) {
    return LibraryState(
      permissionState: permissionState ?? this.permissionState,
      status: status ?? this.status,
      items: items ?? this.items,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      isScanning: isScanning ?? this.isScanning,
      errorMessage: errorMessage,
    );
  }
}

abstract class BaseLibraryNotifier extends Notifier<LibraryState> {
  MediaType get mediaType;
  StreamSubscription<List<MediaItem>>? _subscription;

  /// Repositories that already had their automatic "once per app start" rescan.
  /// Keyed by repository instance so the Music and Videos tabs share one scan
  /// (one scan reads both audio and video) and tests with fresh repos start clean.
  static final Expando<bool> _autoScannedRepos = Expando<bool>('libraryAutoScan');

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);
  MediaPermissionService get _permissionService =>
      ref.read(mediaPermissionServiceProvider);

  @override
  LibraryState build() {
    ref.onDispose(() {
      _subscription?.cancel();
    });

    final permState = mediaType == MediaType.audio
        ? ref.watch(audioPermissionStateProvider)
        : ref.watch(videoPermissionStateProvider);

    Future.microtask(() => _handlePermissionChange(permState));

    return LibraryState(
      permissionState: permState,
      status: (permState == MediaPermissionState.granted || permState == MediaPermissionState.limited)
          ? LibraryStatus.loading
          : (permState == MediaPermissionState.checking ? LibraryStatus.initial : LibraryStatus.success),
      items: const [],
    );
  }

  void _handlePermissionChange(MediaPermissionState permState) {
    state = state.copyWith(permissionState: permState);
    if (permState == MediaPermissionState.granted || permState == MediaPermissionState.limited) {
      if (_subscription == null) {
        state = state.copyWith(status: LibraryStatus.loading);
        _subscribeToMediaItems();
      }
      _autoScanOnce();
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
        await repo.scanDeviceMedia();
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
      state = state.copyWith(permissionState: newState, errorMessage: null);

      if (newState == MediaPermissionState.granted || newState == MediaPermissionState.limited) {
        state = state.copyWith(status: LibraryStatus.loading);
        await scanDevice();
        _subscribeToMediaItems();
      }
    } catch (e, stack) {
      debugPrint('[LibraryNotifier] Error in requestPermission: $e\n$stack');
      state = state.copyWith(
        status: LibraryStatus.error,
        errorMessage: 'Unable to grant permission: $e',
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

  Future<void> scanDevice() async {
    if (state.permissionState != MediaPermissionState.granted && state.permissionState != MediaPermissionState.limited) {
      debugPrint('[LibraryNotifier] scanDevice skipped: permission is not granted (${state.permissionState})');
      return;
    }

    state = state.copyWith(isScanning: true, errorMessage: null);
    try {
      debugPrint('[LibraryNotifier] Starting scanDeviceMedia()...');
      await _repository.scanDeviceMedia();
      debugPrint('[LibraryNotifier] scanDeviceMedia() finished successfully.');
    } catch (e, stack) {
      debugPrint('[LibraryNotifier] scanDevice failed: $e\n$stack');
      state = state.copyWith(
        status: LibraryStatus.error,
        errorMessage: 'Media scan failed: $e',
      );
    } finally {
      state = state.copyWith(isScanning: false);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _subscribeToMediaItems();
  }

  void setSortOption(MediaSortOption sortBy) {
    final isSameOption = state.sortBy == sortBy;
    state = state.copyWith(
      sortBy: sortBy,
      ascending: isSameOption ? !state.ascending : true,
    );
    _subscribeToMediaItems();
  }

  void _subscribeToMediaItems() {
    _subscription?.cancel();
    _subscription = _repository
        .watchMediaItems(
          mediaType: mediaType,
          searchQuery: state.searchQuery,
          sortBy: state.sortBy,
          ascending: state.ascending,
        )
        .listen(
      (items) {
        state = state.copyWith(
          status: LibraryStatus.success,
          items: items,
        );
      },
      onError: (err) {
        state = state.copyWith(
          status: LibraryStatus.error,
          errorMessage: err.toString(),
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
