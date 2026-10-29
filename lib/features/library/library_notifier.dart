import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/media_permission_service.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/library_repository.dart';

final mediaPermissionServiceProvider = Provider<MediaPermissionService>((ref) {
  return MediaPermissionServiceImpl();
});

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

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);
  MediaPermissionService get _permissionService =>
      ref.read(mediaPermissionServiceProvider);

  @override
  LibraryState build() {
    ref.onDispose(() {
      _subscription?.cancel();
    });

    Future.microtask(() => checkPermissionAndInit());

    return const LibraryState(
      permissionState: MediaPermissionState.denied,
      status: LibraryStatus.initial,
      items: [],
    );
  }

  Future<void> checkPermissionAndInit() async {
    final permState = mediaType == MediaType.audio
        ? await _permissionService.checkAudioPermission()
        : await _permissionService.checkVideoPermission();

    if (permState == MediaPermissionState.granted) {
      state = state.copyWith(
        permissionState: MediaPermissionState.granted,
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

      debugPrint('[LibraryNotifier] Permission request result: $newState');
      state = state.copyWith(permissionState: newState, errorMessage: null);

      if (newState == MediaPermissionState.granted) {
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
    if (state.permissionState != MediaPermissionState.granted) {
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
