import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/url_policy.dart';
import '../../data/database/app_database.dart';
import '../../data/downloads/download_engine.dart';
import '../../domain/models/download_state.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/platform_resolver.dart';
import '../music_player/playback_notifier.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();
  String? _inlineUrlError;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      if (_inlineUrlError != null) {
        setState(() => _inlineUrlError = null);
      } else {
        setState(() {});
      }
      return;
    }

    final res = UrlPolicy.validate(text);
    String? errorText;
    if (!res.isValid) {
      switch (res.errorCode) {
        case UrlPolicyErrorCode.invalidScheme:
          errorText = 'Only secure HTTPS links are allowed.';
          break;
        case UrlPolicyErrorCode.userinfoNotAllowed:
          errorText = 'Links containing credentials or usernames are not allowed.';
          break;
        case UrlPolicyErrorCode.blockedIpLiteral:
          errorText = 'Private or internal network addresses are blocked.';
          break;
        case UrlPolicyErrorCode.tooLong:
          errorText = 'Link is too long.';
          break;
        case UrlPolicyErrorCode.invalidHost:
        case UrlPolicyErrorCode.emptyHost:
        case UrlPolicyErrorCode.invalidUri:
        default:
          errorText = 'Please enter a valid web link.';
          break;
      }
    }

    setState(() => _inlineUrlError = errorText);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _urlController.text = data!.text!.trim();
      _onUrlChanged();
      setState(() {});
    }
  }

  void _triggerInspect() {
    _onUrlChanged();
    final inspection = ref.read(inspectionProvider);
    if (_inlineUrlError == null &&
        _urlController.text.trim().isNotEmpty &&
        !inspection.isInspecting) {
      final uri = Uri.tryParse(_urlController.text.trim());
      if (uri != null) {
        ref.read(inspectionProvider.notifier).inspect(uri);
      }
    }
  }

  Future<void> _checkFirstUseAgreement(VoidCallback onAgreed) async {
    final agreed = ref.read(downloadNoticeAgreedProvider);
    if (agreed) {
      onAgreed();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Notice'),
        content: const Text(
          'Only download files you have the right to save. MediaHub does not support unauthorized or copyright-protected content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );

    if (result == true) {
      ref.read(downloadNoticeAgreedProvider.notifier).agree();
      onAgreed();
    }
  }

  Future<void> _startDownload(SourceInfo info) async {
    await _checkFirstUseAgreement(() async {
      final engine = ref.read(downloadEngineProvider);
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final suggestedName = _filenameController.text.trim().isNotEmpty
          ? _filenameController.text.trim()
          : (info.suggestedFilename ?? 'download.bin');

      await engine.enqueueDownload(
        id: id,
        url: info.uri,
        displayName: SafeFilename.sanitize(suggestedName),
        suggestedFileName: suggestedName,
      );

      // Trigger queue processing
      ref.read(downloadQueueCoordinatorProvider.notifier).trigger();

      _urlController.clear();
      _filenameController.clear();
      ref.read(inspectionProvider.notifier).clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download added to queue')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inspection = ref.watch(inspectionProvider);
    final downloadsAsync = ref.watch(downloadsStreamProvider);
    final storageAsync = ref.watch(storageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Informational banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keep MediaHub open while downloading. Downloads pause if the app is closed.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Storage Info Line
          storageAsync.when(
            data: (info) {
              final usedMb = (info.usedBytes / (1024 * 1024)).toStringAsFixed(1);
              final freeGb = (info.freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
              return Text(
                'Space used by downloads: $usedMb MB • Free space: $freeGb GB',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // URL Input Field with Paste & Inspect
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _triggerInspect(),
                  decoration: InputDecoration(
                    labelText: 'Direct Download Link',
                    hintText: 'https://...',
                    errorText: _inlineUrlError,
                    helperText: _inlineUrlError == null ? 'Enter a direct https link to audio or video' : null,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      tooltip: 'Paste from clipboard',
                      onPressed: _pasteFromClipboard,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (inspection.isInspecting) ...[
                SizedBox(
                  height: 54,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          ref.read(inspectionProvider.notifier).cancel();
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(
                  height: 54,
                  child: FilledButton.tonal(
                    onPressed: (_inlineUrlError == null &&
                            _urlController.text.trim().isNotEmpty)
                        ? _triggerInspect
                        : null,
                    child: const Text('Inspect'),
                  ),
                ),
              ],
            ],
          ),
          if (inspection.errorMessage != null && !inspection.isInspecting) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                inspection.errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Inspection Result Card
          if (inspection.result != null) _buildInspectionResultCard(inspection.result!),

          const SizedBox(height: 24),

          // Downloads List
          downloadsAsync.when(
            data: (tasks) => _buildDownloadSections(tasks),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Center(
              child: Text('Failed to load downloads: $err'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionResultCard(SourceInfo info) {
    final inspection = ref.watch(inspectionProvider);
    final knownPlatform = inspection.knownPlatformName;

    if (knownPlatform != null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Platform Link',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text('Host: ${info.uri.host}'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$knownPlatform pages are not direct media files. MediaHub cannot download from this service. Open it in the $knownPlatform app or use its own offline feature.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open link'),
                      onPressed: () async {
                        try {
                          await launchUrl(info.uri, mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isWebPage = info.contentType != null &&
        (info.contentType!.contains('text/html') ||
            info.contentType!.contains('application/xhtml+xml'));

    final isDownloadable = info.isDownloadable && !isWebPage;

    if (_filenameController.text.isEmpty && info.suggestedFilename != null) {
      _filenameController.text = info.suggestedFilename!;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inspection Result',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text('Host: ${info.uri.host}'),
            const SizedBox(height: 4),
            Text('Content Type: ${info.contentType ?? "Unknown"}'),
            const SizedBox(height: 4),
            Text(
              info.contentLength != null
                  ? 'Size: ${(info.contentLength! / (1024 * 1024)).toStringAsFixed(2)} MB'
                  : 'Size: Unknown size',
            ),
            const SizedBox(height: 4),
            Text(
              info.supportsRange
                  ? 'Pause and resume supported'
                  : 'Pause and resume not supported',
            ),
            const SizedBox(height: 12),

            if (isWebPage) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This is a web page, not a media file. MediaHub can only download direct media files that you have the right to save.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open link'),
                      onPressed: () async {
                        try {
                          await launchUrl(info.uri, mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                    ),
                  ],
                ),
              ),
            ] else if (!isDownloadable) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.humanReadableReason ??
                      'This link cannot be downloaded as it is not a direct media file.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _filenameController,
                decoration: const InputDecoration(
                  labelText: 'File Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.file_download_rounded),
                label: const Text('Download'),
                onPressed: () => _startDownload(info),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadSections(List<DownloadEntry> tasks) {
    if (tasks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.download_done_rounded, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('No downloads yet'),
            ],
          ),
        ),
      );
    }

    final active = tasks.where((t) =>
        t.state == DownloadTaskState.downloading.name ||
        t.state == DownloadTaskState.preparing.name ||
        t.state == DownloadTaskState.finalizing.name).toList();

    final queuedOrPaused = tasks.where((t) =>
        t.state == DownloadTaskState.queued.name ||
        t.state == DownloadTaskState.paused.name).toList();

    final completed = tasks.where((t) =>
        t.state == DownloadTaskState.completed.name).toList();

    final failed = tasks.where((t) =>
        t.state == DownloadTaskState.failed.name ||
        t.state == DownloadTaskState.cancelled.name).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (active.isNotEmpty) ...[
          _buildSectionHeader('Active (${active.length})'),
          ...active.map((t) => _buildDownloadRow(t)),
          const SizedBox(height: 16),
        ],
        if (queuedOrPaused.isNotEmpty) ...[
          _buildSectionHeader('Queued / Paused (${queuedOrPaused.length})'),
          ...queuedOrPaused.map((t) => _buildDownloadRow(t)),
          const SizedBox(height: 16),
        ],
        if (completed.isNotEmpty) ...[
          _buildSectionHeader('Completed (${completed.length})'),
          ...completed.map((t) => _buildDownloadRow(t)),
          const SizedBox(height: 16),
        ],
        if (failed.isNotEmpty) ...[
          _buildSectionHeader('Failed / Cancelled (${failed.length})'),
          ...failed.map((t) => _buildDownloadRow(t)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildDownloadRow(DownloadEntry task) {
    final engine = ref.read(downloadEngineProvider);
    final progressAsync = ref.watch(downloadProgressStreamProvider);
    final currentUpdate = progressAsync.asData?.value;

    int received = task.receivedBytes;
    int? total = task.totalBytes;
    double? speed;
    Duration? eta;

    if (currentUpdate != null && currentUpdate.id == task.id) {
      received = currentUpdate.receivedBytes;
      total = currentUpdate.totalBytes ?? total;
      speed = currentUpdate.speedBytesPerSec;
      eta = currentUpdate.eta;
    }

    final double progressVal = (total != null && total > 0)
        ? (received / total).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: task.state == DownloadTaskState.completed.name
            ? () => _playCompletedDownload(task)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStateIcon(task.state),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.fileName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          task.host,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _buildActionButtons(task, engine),
                ],
              ),
              const SizedBox(height: 8),

              // Progress bar
              if (task.state == DownloadTaskState.downloading.name ||
                  task.state == DownloadTaskState.preparing.name) ...[
                LinearProgressIndicator(
                  value: (total != null && total > 0) ? progressVal : null,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(received / (1024 * 1024)).toStringAsFixed(1)} MB'
                      '${total != null ? " / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB" : ""}'
                      '${total != null ? " (${(progressVal * 100).toStringAsFixed(0)}%)" : ""}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (speed != null && speed > 0)
                      Text(
                        '${(speed / 1024).toStringAsFixed(1)} KB/s'
                        '${eta != null ? " • ${eta.inSeconds}s left" : ""}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],

              // State / Error text
              if (task.state == DownloadTaskState.failed.name && task.errorCode != null)
                Text(
                  _formatPlainErrorMessage(task.errorCode!),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                )
              else if (task.state != DownloadTaskState.downloading.name)
                Text(
                  _formatStateText(task.state),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateIcon(String state) {
    if (state == DownloadTaskState.completed.name) {
      return const Icon(Icons.check_circle_rounded, color: Colors.green);
    } else if (state == DownloadTaskState.downloading.name) {
      return const Icon(Icons.downloading_rounded, color: Colors.blue);
    } else if (state == DownloadTaskState.paused.name) {
      return const Icon(Icons.pause_circle_rounded, color: Colors.amber);
    } else if (state == DownloadTaskState.failed.name) {
      return const Icon(Icons.error_outline_rounded, color: Colors.red);
    } else if (state == DownloadTaskState.cancelled.name) {
      return const Icon(Icons.cancel_outlined, color: Colors.grey);
    }
    return const Icon(Icons.schedule_rounded, color: Colors.grey);
  }

  Widget _buildActionButtons(DownloadEntry task, DownloadEngine engine) {
    final state = task.state;
    if (state == DownloadTaskState.downloading.name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause_rounded),
            tooltip: 'Pause',
            onPressed: () => engine.pause(task.id),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            onPressed: () => engine.cancel(task.id),
          ),
        ],
      );
    } else if (state == DownloadTaskState.paused.name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: 'Resume',
            onPressed: () async {
              final db = ref.read(appDatabaseProvider);
              await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
                const DownloadsTableCompanion(state: drift.Value('queued')),
              );
              ref.read(downloadQueueCoordinatorProvider.notifier).trigger();
            },
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            onPressed: () => engine.cancel(task.id),
          ),
        ],
      );
    } else if (state == DownloadTaskState.failed.name || state == DownloadTaskState.cancelled.name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Retry',
            onPressed: () async {
              final db = ref.read(appDatabaseProvider);
              await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
                const DownloadsTableCompanion(
                  state: drift.Value('queued'),
                  errorCode: drift.Value(null),
                ),
              );
              ref.read(downloadQueueCoordinatorProvider.notifier).trigger();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(task),
          ),
        ],
      );
    } else if (state == DownloadTaskState.completed.name) {
      return IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: 'Delete',
        onPressed: () => _confirmDelete(task),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmDelete(DownloadEntry task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text('Delete "${task.fileName}"? Your other files are safe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(appDatabaseProvider);
      // Delete file on disk if exists
      if (task.finalPath != null) {
        final f = File(task.finalPath!);
        if (f.existsSync()) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }

      // Delete media row
      if (task.mediaId != null) {
        await (db.delete(db.mediaItemsTable)..where((tbl) => tbl.id.equals(task.mediaId!))).go();
      }

      // Delete download row
      await (db.delete(db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).go();
    }
  }

  void _playCompletedDownload(DownloadEntry task) {
    if (task.finalPath == null) return;
    final file = File(task.finalPath!);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is missing from device storage.')),
      );
      return;
    }

    final isVideo = task.mimeType != null && task.mimeType!.startsWith('video');
    final mediaItem = MediaItem(
      id: task.mediaId ?? 'dl_${task.id}',
      uri: task.finalPath!,
      mediaType: isVideo ? MediaType.video : MediaType.audio,
      title: task.displayName,
      durationMs: 0,
      sizeBytes: file.lengthSync(),
      dateAdded: task.createdAt,
      source: 'download',
    );

    if (isVideo) {
      context.push('/video_player', extra: mediaItem);
    } else {
      ref.read(playbackNotifierProvider.notifier).loadQueue([mediaItem], autoPlay: true);
    }
  }

  String _formatStateText(String state) {
    switch (state) {
      case 'queued':
        return 'Queued';
      case 'preparing':
        return 'Preparing...';
      case 'downloading':
        return 'Downloading...';
      case 'paused':
        return 'Paused';
      case 'finalizing':
        return 'Finalizing...';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'failed':
        return 'Failed';
      default:
        return state;
    }
  }

  String _formatPlainErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'insufficient_disk_space':
        return 'Not enough free storage space available. Your other files are safe.';
      case 'write_failed':
        return 'Could not save file to disk. Your other files are safe.';
      case 'incomplete_download':
        return 'Connection ended before download was complete. Your other files are safe.';
      case 'not_media':
        return 'The downloaded file was not recognized as media. Your other files are safe.';
      case 'max_size_exceeded':
        return 'Download exceeded the 2GB size limit.';
      case 'content_range_mismatch':
        return 'Server sent invalid partial content.';
      default:
        if (errorCode.startsWith('http_')) {
          return 'Server returned error (${errorCode.replaceFirst('http_', 'HTTP ')}).';
        }
        return 'Download failed. Please check your connection and try again.';
    }
  }
}
