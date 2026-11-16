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
import '../../core/platform_info.dart';
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

/// Latest progress update per download id. The UI used to keep only the very
/// last update of any task, so two parallel downloads made each other's speed
/// and ETA flicker.
class DownloadProgressMapNotifier extends Notifier<Map<String, DownloadProgressUpdate>> {
  @override
  Map<String, DownloadProgressUpdate> build() {
    final engine = ref.watch(downloadEngineProvider);
    final sub = engine.progressStream.listen((u) {
      state = {...state, u.id: u};
    });
    ref.onDispose(sub.cancel);
    return const {};
  }
}

final downloadProgressMapProvider =
    NotifierProvider<DownloadProgressMapNotifier, Map<String, DownloadProgressUpdate>>(
  DownloadProgressMapNotifier.new,
);

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
  Timer? _notificationPeriodicTimer;
  StreamSubscription? _actionEventsSub;

  @override
  void build() {
    final serviceController = ref.watch(downloadServiceControllerProvider);
    _actionEventsSub = serviceController.actionEvents.listen((event) async {
      final db = ref.read(appDatabaseProvider);
      if (event == 'pauseAll' || event == 'timeout') {
        final active = await (db.select(db.downloadsTable)
              ..where((t) =>
                  t.state.equals(DownloadTaskState.downloading.name) |
                  t.state.equals(DownloadTaskState.preparing.name) |
                  t.state.equals(DownloadTaskState.queued.name)))
            .get();
        for (final t in active) {
          await pauseTask(t);
        }
        await serviceController.stopService();
      }
    });

    ref.onDispose(() {
      _actionEventsSub?.cancel();
      _notificationPeriodicTimer?.cancel();
    });
  }

  void _startNotificationTimer() {
    if (_notificationPeriodicTimer != null) return;
    _notificationPeriodicTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateAggregateNotification();
    });
  }

  void _stopNotificationTimer() {
    _notificationPeriodicTimer?.cancel();
    _notificationPeriodicTimer = null;
  }

  Future<void> _updateAggregateNotification() async {
    final db = ref.read(appDatabaseProvider);
    final serviceController = ref.read(downloadServiceControllerProvider);

    final activeTasks = await (db.select(db.downloadsTable)
          ..where((t) =>
              t.state.equals(DownloadTaskState.downloading.name) |
              t.state.equals(DownloadTaskState.preparing.name) |
              t.state.equals(DownloadTaskState.finalizing.name)))
        .get();

    if (activeTasks.isEmpty) {
      final queued = await (db.select(db.downloadsTable)
            ..where((t) => t.state.equals(DownloadTaskState.queued.name)))
          .get();
      if (queued.isEmpty) {
        _stopNotificationTimer();
        await serviceController.stopService();
        return;
      }
      serviceController.updateProgress(count: queued.length, percent: -1);
      return;
    }

    int totalReceived = 0;
    int totalExpected = 0;
    bool anyUnknownSize = false;

    for (final t in activeTasks) {
      totalReceived += t.receivedBytes;
      if (t.totalBytes != null && t.totalBytes! > 0) {
        totalExpected += t.totalBytes!;
      } else {
        anyUnknownSize = true;
      }
    }

    int aggregatePercent = -1;
    if (!anyUnknownSize && totalExpected > 0) {
      aggregatePercent = ((totalReceived / totalExpected) * 100).clamp(0, 100).toInt();
    }

    final singleFileName = activeTasks.length == 1 ? activeTasks.first.fileName : null;

    serviceController.updateProgress(
      count: activeTasks.length,
      percent: aggregatePercent,
      fileName: singleFileName,
    );
  }

  Future<void> trigger() async {
    final db = ref.read(appDatabaseProvider);
    final engine = ref.read(downloadEngineProvider);
    final serviceController = ref.read(downloadServiceControllerProvider);
    final tasks = await (db.select(db.downloadsTable)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    final activeDownloadingCount = tasks
        .where((t) =>
            t.state == DownloadTaskState.downloading.name ||
            t.state == DownloadTaskState.preparing.name ||
            t.state == DownloadTaskState.finalizing.name)
        .length;

    final queuedTasks = tasks.where((t) => t.state == DownloadTaskState.queued.name).toList();

    // Start or stop foreground service & 1s notification timer
    if (activeDownloadingCount > 0 || queuedTasks.isNotEmpty) {
      final singleTask = tasks.where((t) => t.state == DownloadTaskState.downloading.name).firstOrNull;
      await serviceController.startService(
        count: activeDownloadingCount > 0 ? activeDownloadingCount : queuedTasks.length,
        fileName: activeDownloadingCount == 1 ? singleTask?.fileName : null,
      );
      _startNotificationTimer();
    } else {
      _stopNotificationTimer();
      await serviceController.stopService();
    }

    // _runningTaskIds is updated synchronously, the DB state a moment later:
    // use whichever is larger so rapid trigger() calls cannot exceed 2 workers.
    final busy = activeDownloadingCount > _runningTaskIds.length
        ? activeDownloadingCount
        : _runningTaskIds.length;
    if (busy >= 2) return;

    final nextQueued = queuedTasks;
    int slotsAvailable = 2 - busy;

    for (final task in nextQueued) {
      if (slotsAvailable <= 0) break;
      if (!_runningTaskIds.contains(task.id)) {
        _runningTaskIds.add(task.id);
        slotsAvailable--;
        final Future<void> job = task.engine == 'extractor'
            ? ref.read(extractorDownloadRunnerProvider).run(task.id)
            : engine.runTask(task.id);
        job.whenComplete(() {
          _runningTaskIds.remove(task.id);
          trigger();
        });
      }
    }
  }

  /// Pause a task with the engine that owns it.
  Future<void> pauseTask(DownloadEntry task) {
    if (task.engine == 'extractor') {
      return ref.read(extractorDownloadRunnerProvider).pause(task.id);
    }
    return ref.read(downloadEngineProvider).pause(task.id);
  }

  /// Cancel a task with the engine that owns it.
  Future<void> cancelTask(DownloadEntry task) {
    if (task.engine == 'extractor') {
      return ref.read(extractorDownloadRunnerProvider).cancel(task.id);
    }
    return ref.read(downloadEngineProvider).cancel(task.id);
  }

  /// Called once at app start: repairs tasks that were interrupted by the app
  /// being killed and resumes them (and anything still queued).
  Future<void> recoverAndResume() async {
    if (!PlatformInfo.supportsDownloads) return;
    await ref.read(downloadDirectoryProvider.future);
    final db = ref.read(appDatabaseProvider);
    final engine = ref.read(downloadEngineProvider);
    final httpIds = await engine.reconcileOnStartup();
    for (final id in httpIds) {
      await (db.update(db.downloadsTable)..where((t) => t.id.equals(id))).write(
        const DownloadsTableCompanion(state: Value('queued')),
      );
    }
    await ref.read(extractorDownloadRunnerProvider).reconcileOnStartup();
    await trigger();
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

/// Reads once from main() after the first frame to recover interrupted downloads.
final downloadStartupProvider = FutureProvider<void>((ref) async {
  await ref.read(downloadQueueCoordinatorProvider.notifier).recoverAndResume();
});
