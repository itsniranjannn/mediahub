import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/downloads/known_platform_checker.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/direct_url_resolver.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/download_state.dart';
import '../../domain/repositories/platform_resolver.dart';
import '../music_player/playback_notifier.dart';
import 'download_providers.dart';

class InspectionState {
  final bool isInspecting;
  final SourceInfo? result;
  final String? errorMessage;
  final String? knownPlatformName;

  const InspectionState({
    this.isInspecting = false,
    this.result,
    this.errorMessage,
    this.knownPlatformName,
  });
}

class InspectionNotifier extends Notifier<InspectionState> {
  DirectUrlResolver? _resolver;
  CancelableOperation? _activeOperation;

  @override
  InspectionState build() {
    _resolver = DirectUrlResolver();
    return const InspectionState();
  }

  void setResolverForTesting(DirectUrlResolver resolver) {
    _resolver = resolver;
  }

  Future<void> inspect(Uri uri) async {
    cancel();

    // Check if URL belongs to a known platform first (no network call needed)
    final platform = KnownPlatformChecker.matchPlatformName(uri);
    if (platform != null) {
      state = InspectionState(
        isInspecting: false,
        knownPlatformName: platform,
        result: SourceInfo(
          providerId: 'known_platform',
          uri: uri,
          capabilities: {},
        ),
      );
      return;
    }

    state = const InspectionState(isInspecting: true);

    bool isCancelled = false;
    _activeOperation = CancelableOperation(
      onCancel: () {
        isCancelled = true;
      },
    );

    try {
      final info = await _resolver!.inspect(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Inspection timed out. The server did not respond in time.');
        },
      );

      if (!isCancelled) {
        state = InspectionState(isInspecting: false, result: info);
      }
    } on TimeoutException {
      if (!isCancelled) {
        state = const InspectionState(
          isInspecting: false,
          errorMessage: 'Inspection timed out. Please check your network and try again.',
        );
      }
    } catch (e) {
      if (!isCancelled) {
        state = const InspectionState(
          isInspecting: false,
          errorMessage: 'Unable to inspect link. Please ensure it is a valid direct link.',
        );
      }
    } finally {
      _activeOperation = null;
    }
  }

  void cancel() {
    if (state.isInspecting) {
      _activeOperation?.cancel();
      _activeOperation = null;
      state = const InspectionState(
        isInspecting: false,
        errorMessage: 'Inspection was cancelled.',
      );
    }
  }

  void clear() {
    _activeOperation?.cancel();
    _activeOperation = null;
    state = const InspectionState();
  }
}

class CancelableOperation {
  final VoidCallback onCancel;
  CancelableOperation({required this.onCancel});
  void cancel() => onCancel();
}

final inspectionProvider =
    NotifierProvider<InspectionNotifier, InspectionState>(InspectionNotifier.new);

// Stream provider for all downloads in DB
final downloadsStreamProvider = StreamProvider.autoDispose<List<DownloadEntry>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.downloadsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

// Stream provider for progress emissions
final downloadProgressStreamProvider =
    StreamProvider.autoDispose<DownloadProgressUpdate>((ref) {
  final engine = ref.watch(downloadEngineProvider);
  return engine.progressStream;
});

// Storage space info provider
class StorageInfo {
  final int usedBytes;
  final int freeBytes;

  const StorageInfo({required this.usedBytes, required this.freeBytes});
}

final storageInfoProvider = FutureProvider.autoDispose<StorageInfo>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final downloads = await db.select(db.downloadsTable).get();

  int used = 0;
  for (final d in downloads) {
    used += d.receivedBytes;
  }

  int free = 10 * 1024 * 1024 * 1024;
  try {
    const channel = MethodChannel('mediahub/media_store');
    final res = await channel.invokeMethod<int>('freeSpaceBytes');
    if (res != null) free = res;
  } catch (_) {}

  return StorageInfo(usedBytes: used, freeBytes: free);
});

// Download Queue Coordinator (Max 2 simultaneous downloads)
class DownloadQueueCoordinatorNotifier extends Notifier<void> {
  final Set<String> _runningTaskIds = {};

  @override
  void build() {}

  Future<void> trigger() async {
    final db = ref.read(appDatabaseProvider);
    final engine = ref.read(downloadEngineProvider);
    final tasks = await (db.select(db.downloadsTable)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    final activeDownloadingCount = tasks
        .where((t) =>
            t.state == DownloadTaskState.downloading.name ||
            t.state == DownloadTaskState.preparing.name ||
            t.state == DownloadTaskState.finalizing.name)
        .length;

    if (activeDownloadingCount >= 2) return;

    final nextQueued = tasks.where((t) => t.state == DownloadTaskState.queued.name).toList();
    int slotsAvailable = 2 - activeDownloadingCount;

    for (final task in nextQueued) {
      if (slotsAvailable <= 0) break;
      if (!_runningTaskIds.contains(task.id)) {
        _runningTaskIds.add(task.id);
        slotsAvailable--;
        engine.runTask(task.id).whenComplete(() {
          _runningTaskIds.remove(task.id);
          trigger();
        });
      }
    }
  }
}

final downloadQueueCoordinatorProvider =
    NotifierProvider<DownloadQueueCoordinatorNotifier, void>(
  DownloadQueueCoordinatorNotifier.new,
);

// First use warning dialog agreement flag
class DownloadNoticeAgreedNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void agree() {
    state = true;
  }
}

final downloadNoticeAgreedProvider =
    NotifierProvider<DownloadNoticeAgreedNotifier, bool>(
  DownloadNoticeAgreedNotifier.new,
);
