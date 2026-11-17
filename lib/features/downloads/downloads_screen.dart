import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/platform_info.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/url_policy.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/database/app_database.dart';
import '../../domain/models/download_state.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/platform_resolver.dart';
import '../../shared/widgets/ui_kit.dart';
import '../music_player/playback_notifier.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/personal_tools_notifier.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';
import 'web_link_download_flow.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  /// Owned here (the download flows clear it); validated and edited inside
  /// [_UrlCard] so typing only rebuilds that card, not the download list.
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();
  bool _notificationPermissionDenied = false;

  /// null = everything, 'video' or 'audio'
  String? _kindFilter;

  @override
  void dispose() {
    _urlController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  /// Android 13+: ask for the notification permission on the first download.
  Future<void> _ensureNotificationPermission() async {
    final granted = await WebLinkDownloadFlow.ensureNotificationPermission();
    if (!granted && mounted) {
      setState(() => _notificationPermissionDenied = true);
    }
  }

  /// The web link downloader action shown next to "Open link" (null when the
  /// downloader is not available on this device).
  Widget? _fetchFormatsAction(Uri uri) {
    if (!PlatformInfo.supportsWebLinkDownloader || !kPersonalToolsEnabled) {
      return null;
    }
    final enabled = ref.watch(personalToolsProvider).isEnabled;
    if (!enabled) {
      return TextButton.icon(
        icon: const Icon(Icons.settings_outlined),
        label: const Text('Enable downloader'),
        onPressed: () => context.push('/settings'),
      );
    }
    return FilledButton.icon(
      icon: const Icon(Icons.video_library_rounded),
      label: const Text('Choose quality'),
      onPressed: () => _fetchFormats(uri),
    );
  }

  Future<void> _fetchFormats(Uri uri) {
    return WebLinkDownloadFlow.start(
      context,
      ref,
      uri,
      onQueued: () {
        _urlController.clear();
        _filenameController.clear();
        ref.read(inspectionProvider.notifier).clear();
      },
      onNotificationDenied: () {
        if (mounted) setState(() => _notificationPermissionDenied = true);
      },
    );
  }

  Future<void> _startDownload(SourceInfo info) async {
    await _ensureNotificationPermission();

    if (!mounted) return;
    if (await WebLinkDownloadFlow.confirmNotice(context, ref)) {
      final engine = ref.read(downloadEngineProvider);
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final suggestedName = _filenameController.text.trim().isNotEmpty
          ? _filenameController.text.trim()
          : (info.suggestedFilename ?? 'download.bin');

      final contentType = info.contentType ?? '';
      await engine.enqueueDownload(
        id: id,
        url: info.uri,
        displayName: SafeFilename.sanitize(suggestedName),
        suggestedFileName: suggestedName,
        kind: contentType.startsWith('video')
            ? 'video'
            : (contentType.startsWith('audio') ? 'audio' : null),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final inspection = ref.watch(inspectionProvider);
    final downloadsAsync = ref.watch(downloadsStreamProvider);
    final storageAsync = ref.watch(storageInfoProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
              sliver: SliverList.list(
                children: [
                  const _Header(),
                  _UrlCard(controller: _urlController),
                  if (inspection.errorMessage != null && !inspection.isInspecting) ...[
                    const SizedBox(height: AppSpacing.md12),
                    _Callout(
                      icon: Icons.error_outline_rounded,
                      color: AppColors.error,
                      text: inspection.errorMessage!,
                    ),
                  ],
                  if (inspection.result != null) ...[
                    const SizedBox(height: AppSpacing.lg16),
                    _buildInspectionResultCard(inspection.result!),
                  ],
                  if (_notificationPermissionDenied) ...[
                    const SizedBox(height: AppSpacing.md12),
                    const _Callout(
                      icon: Icons.notifications_off_outlined,
                      color: AppColors.warning,
                      text:
                          'Notifications are disabled. Downloads still run in the background, but progress will not show in the status bar.',
                    ),
                  ],
                  const SectionHeader(
                    title: 'Your downloads',
                    padding: EdgeInsets.fromLTRB(0, AppSpacing.xxl24, 0, AppSpacing.xs4),
                  ),
                  storageAsync.when(
                    data: (info) => _StorageStats(info: info),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppSpacing.md12),
                ],
              ),
            ),
            ...downloadsAsync.when(
              data: _downloadSlivers,
              loading: () => const [
                SliverToBoxAdapter(child: _SkeletonRows()),
                _BackgroundNoticeSliver.end(),
              ],
              error: (err, _) => [
                SliverToBoxAdapter(
                  child: EmptyHint(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load downloads',
                    message: 'Failed to load downloads: $err',
                  ),
                ),
                const _BackgroundNoticeSliver.end(),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
          ],
        ),
      ),
    );
  }

  Widget _openLinkButton(Uri uri) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.open_in_browser_rounded),
      label: const Text('Open link'),
      onPressed: () async {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
    );
  }

  Widget _linkActions(Uri uri) {
    final fetchAction = _fetchFormatsAction(uri);
    return Wrap(
      spacing: AppSpacing.sm8,
      runSpacing: AppSpacing.sm8,
      children: [
        _openLinkButton(uri),
        ?fetchAction,
      ],
    );
  }

  Widget _buildInspectionResultCard(SourceInfo info) {
    final inspection = ref.watch(inspectionProvider);
    final knownPlatform = inspection.knownPlatformName;
    final downloaderEnabled = PlatformInfo.supportsWebLinkDownloader &&
        kPersonalToolsEnabled &&
        ref.watch(personalToolsProvider).isEnabled;

    if (knownPlatform != null) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.public_rounded,
              color: downloaderEnabled ? AppColors.primary : AppColors.warning,
              title: 'Platform Link',
              subtitle: 'Host: ${info.uri.host}',
              trailing: PillTag(text: knownPlatform),
            ),
            const SizedBox(height: AppSpacing.lg16),
            _Callout(
              icon: downloaderEnabled ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
              color: downloaderEnabled ? AppColors.primary : AppColors.warning,
              text: downloaderEnabled
                  ? '$knownPlatform link detected. Tap "Choose quality" to download the public video or audio. Only save content you have the right to download.'
                  : '$knownPlatform pages are not direct media files. Turn on "Enable web link downloader" in Settings to download public videos, or open the link in the $knownPlatform app.',
            ),
            const SizedBox(height: AppSpacing.md12),
            _linkActions(info.uri),
          ],
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

    final contentType = info.contentType ?? '';
    final IconData headerIcon;
    final Color headerColor;
    if (isWebPage) {
      headerIcon = Icons.language_rounded;
      headerColor = AppColors.warning;
    } else if (!isDownloadable) {
      headerIcon = Icons.link_off_rounded;
      headerColor = AppColors.error;
    } else if (contentType.startsWith('video')) {
      headerIcon = Icons.video_file_rounded;
      headerColor = AppColors.accent;
    } else if (contentType.startsWith('audio')) {
      headerIcon = Icons.audio_file_rounded;
      headerColor = AppColors.primary;
    } else {
      headerIcon = Icons.insert_drive_file_rounded;
      headerColor = AppColors.primary;
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: headerIcon,
            color: headerColor,
            title: 'Inspection Result',
            subtitle: 'Host: ${info.uri.host}',
          ),
          const SizedBox(height: AppSpacing.sm8),
          _DetailLine(
            icon: Icons.description_outlined,
            text: 'Content Type: ${info.contentType ?? "Unknown"}',
          ),
          _DetailLine(
            icon: Icons.data_usage_rounded,
            text: info.contentLength != null
                ? 'Size: ${(info.contentLength! / (1024 * 1024)).toStringAsFixed(2)} MB'
                : 'Size: Unknown size',
          ),
          _DetailLine(
            icon: info.supportsRange ? Icons.pause_circle_outline_rounded : Icons.block_rounded,
            text: info.supportsRange
                ? 'Pause and resume supported'
                : 'Pause and resume not supported',
          ),
          const SizedBox(height: AppSpacing.lg16),
          if (isWebPage) ...[
            const _Callout(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              text:
                  'This is a web page, not a media file. MediaHub can only download direct media files that you have the right to save.',
            ),
            const SizedBox(height: AppSpacing.md12),
            _linkActions(info.uri),
          ] else if (!isDownloadable) ...[
            _Callout(
              icon: Icons.block_rounded,
              color: AppColors.error,
              text: info.humanReadableReason ??
                  'This link cannot be downloaded as it is not a direct media file.',
            ),
          ] else ...[
            TextField(
              controller: _filenameController,
              style: AppTypography.body,
              decoration: const InputDecoration(
                labelText: 'File name',
                prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.file_download_rounded),
                label: const Text('Download'),
                onPressed: () => _startDownload(info),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _downloadSlivers(List<DownloadEntry> all) {
    if (all.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: EmptyHint(
            icon: Icons.download_rounded,
            title: 'No downloads yet',
            message: 'Paste a link above to save music or videos for offline use.',
          ),
        ),
        _BackgroundNoticeSliver.end(),
      ];
    }

    // The "swipe away pauses downloads" note matters while something is
    // running or waiting: then it sits right under the storage line, above the
    // list, where it cannot be missed. With nothing in progress it goes after
    // the list. (The switch happens when a row changes group, which reflows
    // the list anyway.)
    final hasInProgress = all.any((t) =>
        _isActiveState(t.state) ||
        t.state == DownloadTaskState.queued.name ||
        t.state == DownloadTaskState.paused.name);

    final counts = <String?, int>{
      null: all.length,
      'video': all.where((t) => _kindOf(t) == 'video').length,
      'audio': all.where((t) => _kindOf(t) == 'audio').length,
    };
    final tasks = _kindFilter == null ? all : all.where((t) => _kindOf(t) == _kindFilter).toList();

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

    // Flattened list of group labels and rows, built lazily below. Every item
    // is keyed and indexed so a row that moves (Active -> Completed) keeps its
    // element and state instead of rebuilding every card below it.
    final rows = <Object>[];
    final indexByKey = <Key, int>{};
    void addGroup(String title, List<DownloadEntry> group) {
      if (group.isEmpty) return;
      final label = _GroupLabel(title, group.length);
      indexByKey[label.key] = rows.length;
      rows.add(label);
      for (final task in group) {
        indexByKey[ValueKey<String>(task.id)] = rows.length;
        rows.add(task);
      }
    }

    addGroup('Active', active);
    addGroup('Queued / Paused', queuedOrPaused);
    addGroup('Completed', completed);
    addGroup('Failed / Cancelled', failed);

    final isVideoFilter = _kindFilter == 'video';

    return [
      if (hasInProgress) const _BackgroundNoticeSliver.top(),
      SliverPadding(
        key: const ValueKey('kind-filter'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        sliver: SliverToBoxAdapter(child: _buildKindFilter(counts)),
      ),
      if (tasks.isEmpty)
        SliverToBoxAdapter(
          key: const ValueKey('kind-empty'),
          child: EmptyHint(
            icon: isVideoFilter ? Icons.videocam_off_rounded : Icons.music_off_rounded,
            title: isVideoFilter ? 'No video downloads' : 'No audio downloads',
            message: isVideoFilter
                ? 'Videos you download will show up here.'
                : 'Music and audio you download will show up here.',
          ),
        ),
      SliverPadding(
        key: const ValueKey('downloads-list'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        sliver: SliverList.builder(
          itemCount: rows.length,
          findChildIndexCallback: (key) => indexByKey[key],
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _GroupLabel) {
              return _GroupHeader(key: row.key, title: row.title, count: row.count);
            }
            final task = row as DownloadEntry;
            final isCompleted = task.state == DownloadTaskState.completed.name;
            return Padding(
              key: ValueKey<String>(task.id),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
              child: _DownloadCard(
                task: task,
                actions: _buildActionButtons(task),
                onTap: isCompleted ? () => _playCompletedDownload(task) : null,
              ),
            );
          },
        ),
      ),
      if (!hasInProgress) const _BackgroundNoticeSliver.end(),
    ];
  }

  Widget _buildKindFilter(Map<String?, int> counts) {
    Widget chip(String label, String? value, IconData icon) {
      final selected = _kindFilter == value;
      return ChoiceChip(
        avatar: Icon(
          icon,
          size: 16,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        ),
        label: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              TextSpan(
                text: '  ${counts[value] ?? 0}',
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        labelStyle: AppTypography.metadata.copyWith(
          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary.withValues(alpha: 0.5) : AppColors.divider,
        ),
        selected: selected,
        onSelected: (_) => setState(() => _kindFilter = value),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs4),
      child: Wrap(
        spacing: AppSpacing.sm8,
        runSpacing: AppSpacing.sm8,
        children: [
          chip('All', null, Icons.apps_rounded),
          chip('Video', 'video', Icons.videocam_rounded),
          chip('Audio', 'audio', Icons.music_note_rounded),
        ],
      ),
    );
  }

  Widget _buildActionButtons(DownloadEntry task) {
    final state = task.state;
    final coordinator = ref.read(downloadQueueCoordinatorProvider.notifier);
    if (_isActiveState(state)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RowAction(
            icon: Icons.pause_rounded,
            tooltip: 'Pause',
            emphasized: true,
            onPressed: () => coordinator.pauseTask(task),
          ),
          _RowAction(
            icon: Icons.close_rounded,
            tooltip: 'Cancel',
            onPressed: () => coordinator.cancelTask(task),
          ),
        ],
      );
    } else if (state == DownloadTaskState.queued.name) {
      return _RowAction(
        icon: Icons.close_rounded,
        tooltip: 'Cancel',
        onPressed: () => coordinator.cancelTask(task),
      );
    } else if (state == DownloadTaskState.paused.name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RowAction(
            icon: Icons.play_arrow_rounded,
            tooltip: 'Resume',
            emphasized: true,
            onPressed: () async {
              final db = ref.read(appDatabaseProvider);
              await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
                const DownloadsTableCompanion(state: drift.Value('queued')),
              );
              coordinator.trigger();
            },
          ),
          _RowAction(
            icon: Icons.close_rounded,
            tooltip: 'Cancel',
            onPressed: () => coordinator.cancelTask(task),
          ),
        ],
      );
    } else if (state == DownloadTaskState.failed.name || state == DownloadTaskState.cancelled.name) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RowAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Retry',
            emphasized: true,
            onPressed: () async {
              final db = ref.read(appDatabaseProvider);
              await (db.update(db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
                const DownloadsTableCompanion(
                  state: drift.Value('queued'),
                  errorCode: drift.Value(null),
                ),
              );
              coordinator.trigger();
            },
          ),
          _RowAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(task),
          ),
        ],
      );
    } else if (state == DownloadTaskState.completed.name) {
      return _RowAction(
        icon: Icons.delete_outline_rounded,
        tooltip: 'Delete',
        onPressed: () => _confirmDelete(task),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmDelete(DownloadEntry task) async {
    // Read while the screen is surely mounted: `ref.read` throws once it is
    // gone, and the screen can go away while the dialog is open. With both
    // captured here a confirmed delete still completes.
    final db = ref.read(appDatabaseProvider);
    final runner = task.engine == 'extractor' ? ref.read(extractorDownloadRunnerProvider) : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
        title: const Text('Delete Download'),
        content: Text(
          'Delete "${breakableTitle(task.fileName)}"? Your other files are safe.',
          semanticsLabel: 'Delete "${task.fileName}"? Your other files are safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.background,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Delete files on disk if they exist (media + cover image)
      for (final path in [task.finalPath, task.thumbnailPath]) {
        if (path == null) continue;
        final f = File(path);
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

      // A web-link (yt-dlp) task keeps partial / intermediate files under
      // downloads/ytdlp/ for a resumable retry; with the row gone they are
      // garbage. Cleanup only: it never blocks the delete (startup sweeps too).
      if (runner != null) {
        try {
          await runner.deleteWorkFiles(task.id);
        } catch (_) {}
      }
    }
  }

  Future<void> _playCompletedDownload(DownloadEntry task) async {
    if (task.finalPath == null) return;
    final file = File(task.finalPath!);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is missing from device storage.')),
      );
      return;
    }

    final db = ref.read(appDatabaseProvider);
    MediaItem? item;
    if (task.mediaId != null) {
      final row = await (db.select(db.mediaItemsTable)..where((t) => t.id.equals(task.mediaId!)))
          .getSingleOrNull();
      item = row?.toDomain();
    }
    final isVideoByMime = task.mimeType != null && task.mimeType!.startsWith('video');
    item ??= MediaItem(
      id: task.mediaId ?? 'dl_${task.id}',
      uri: task.finalPath!,
      mediaType: (task.kind == 'video' || isVideoByMime) ? MediaType.video : MediaType.audio,
      title: task.displayName,
      durationMs: 0,
      sizeBytes: file.lengthSync(),
      dateAdded: task.createdAt,
      source: 'download',
      artworkPath: task.thumbnailPath,
    );
    if (!mounted) return;

    if (item.mediaType == MediaType.video) {
      context.push('/video_player', extra: item);
      return;
    }

    // Audio: queue every downloaded song so next/previous work, starting at the tapped one.
    final rows = await (db.select(db.mediaItemsTable)
          ..where((t) => t.source.equals('download') & t.mediaType.equals(MediaType.audio.name))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.dateAdded)]))
        .get();
    final queue = rows.map((r) => r.toDomain()).toList();
    final index = queue.indexWhere((m) => m.id == item!.id);
    if (!mounted) return;
    if (index < 0) {
      ref.read(playbackNotifierProvider.notifier).loadQueue([item], autoPlay: true);
    } else {
      ref.read(playbackNotifierProvider.notifier).loadQueue(queue, startIndex: index, autoPlay: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/// Inline message for a link that fails [UrlPolicy], or null when it passes.
/// An empty field is not an error.
String? _urlErrorText(String text) {
  if (text.isEmpty) return null;
  final res = UrlPolicy.validate(text);
  if (res.isValid) return null;
  switch (res.errorCode) {
    case UrlPolicyErrorCode.invalidScheme:
      return 'Only secure HTTPS links are allowed.';
    case UrlPolicyErrorCode.userinfoNotAllowed:
      return 'Links containing credentials or usernames are not allowed.';
    case UrlPolicyErrorCode.blockedIpLiteral:
      return 'Private or internal network addresses are blocked.';
    case UrlPolicyErrorCode.tooLong:
      return 'Link is too long.';
    case UrlPolicyErrorCode.invalidHost:
    case UrlPolicyErrorCode.emptyHost:
    case UrlPolicyErrorCode.invalidUri:
    default:
      return 'Please enter a valid web link.';
  }
}

bool _isActiveState(String state) =>
    state == DownloadTaskState.downloading.name ||
    state == DownloadTaskState.preparing.name ||
    state == DownloadTaskState.finalizing.name;

String? _kindOf(DownloadEntry task) {
  if (task.kind != null) return task.kind;
  final mime = task.mimeType;
  if (mime == null) return null;
  return mime.startsWith('video') ? 'video' : 'audio';
}

/// Icon and colour of the small badge on a row thumbnail.
(IconData, Color) _stateVisual(String state) {
  if (state == DownloadTaskState.completed.name) {
    return (Icons.check_circle_rounded, AppColors.success);
  } else if (_isActiveState(state)) {
    return (Icons.downloading_rounded, AppColors.primary);
  } else if (state == DownloadTaskState.paused.name) {
    return (Icons.pause_circle_rounded, AppColors.warning);
  } else if (state == DownloadTaskState.failed.name) {
    return (Icons.error_rounded, AppColors.error);
  } else if (state == DownloadTaskState.cancelled.name) {
    return (Icons.cancel_rounded, AppColors.textMuted);
  }
  return (Icons.schedule_rounded, AppColors.textMuted);
}

/// Colour of the one-word status line under a row.
Color _stateTextColor(String state) {
  if (state == DownloadTaskState.completed.name) return AppColors.success;
  if (state == DownloadTaskState.paused.name) return AppColors.warning;
  if (state == DownloadTaskState.failed.name) return AppColors.error;
  if (state == DownloadTaskState.finalizing.name) return AppColors.primary;
  if (state == DownloadTaskState.cancelled.name) return AppColors.textMuted;
  return AppColors.textSecondary;
}

String _formatEta(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}

String _formatStateText(String state, [DownloadEntry? task]) {
  if (state == 'finalizing' && task != null && task.engine == 'extractor') {
    return task.audioFormat != null ? 'Converting audio...' : 'Merging video and audio...';
  }
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
    case 'size_mismatch':
      return 'The downloaded file size did not match the server. Please retry.';
    case 'x_login_required':
      return 'This video needs a login. Only public videos can be downloaded.';
    case 'x_private_content':
      return 'This video is private and cannot be downloaded.';
    case 'x_drm_protected':
      return 'This content is DRM protected and cannot be downloaded.';
    case 'x_not_found':
      return 'The video was not found. It may have been removed.';
    case 'x_file_too_large':
      return 'The video is larger than the 2 GB limit.';
    case 'x_network_error':
      return 'Network problem while downloading. Check your connection and retry.';
    case 'x_no_output':
      return 'The downloader finished but produced no file. Please retry.';
    case 'x_host_not_allowed':
      return 'This website is not supported by the web link downloader.';
    case 'x_init_failed':
    case 'x_init_error':
      return 'The downloader engine could not start. Please retry.';
    case 'x_extraction_failed':
      return 'Could not fetch this video. The site may have changed: update the downloader engine in Settings, then retry.';
    default:
      if (errorCode.startsWith('x_')) {
        return 'Web link download failed. Update the downloader engine in Settings and retry.';
      }
      if (errorCode.startsWith('http_')) {
        return 'Server returned error (${errorCode.replaceFirst('http_', 'HTTP ')}).';
      }
      return 'Download failed. Please check your connection and try again.';
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl20, bottom: AppSpacing.md12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Downloads', style: AppTypography.display)),
          const SizedBox(height: AppSpacing.xs4),
          Text(
            'Save music and videos from a link to enjoy offline.',
            style: AppTypography.metadata,
          ),
        ],
      ),
    );
  }
}

/// One card holding the link field (with paste) and the Inspect action.
///
/// Keeps its own validation state and listens to [controller] itself, so a
/// keystroke rebuilds only this card (and only when the error or the empty /
/// non-empty state actually changes), never the download list below.
class _UrlCard extends ConsumerStatefulWidget {
  final TextEditingController controller;

  const _UrlCard({required this.controller});

  @override
  ConsumerState<_UrlCard> createState() => _UrlCardState();
}

class _UrlCardState extends ConsumerState<_UrlCard> {
  String? _inlineUrlError;
  bool _hasText = false;

  /// Android bundles yt-dlp, so YouTube, Instagram and other supported sites
  /// can be downloaded there while "Enable web link downloader" is on (the
  /// same rule as the inspection card); otherwise (iOS, or the setting off)
  /// only direct media links work. Called from [build]: it watches only the
  /// on / off flag, so a keystroke still rebuilds nothing else.
  String get _linkHelperText {
    final downloaderEnabled = PlatformInfo.supportsWebLinkDownloader &&
        kPersonalToolsEnabled &&
        ref.watch(personalToolsProvider.select((s) => s.isEnabled));
    return downloaderEnabled
        ? 'Paste a YouTube, Instagram or direct https link'
        : 'Enter a direct https link to audio or video';
  }

  @override
  void initState() {
    super.initState();
    _syncFromText();
    widget.controller.addListener(_onUrlChanged);
  }

  @override
  void didUpdateWidget(covariant _UrlCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onUrlChanged);
      widget.controller.addListener(_onUrlChanged);
      _syncFromText();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUrlChanged);
    super.dispose();
  }

  /// Recomputes the validation state from the current text (no rebuild).
  /// Returns whether anything changed.
  bool _syncFromText() {
    final text = widget.controller.text.trim();
    final error = _urlErrorText(text);
    final hasText = text.isNotEmpty;
    if (error == _inlineUrlError && hasText == _hasText) return false;
    _inlineUrlError = error;
    _hasText = hasText;
    return true;
  }

  void _onUrlChanged() {
    if (_syncFromText()) setState(() {});
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    if (data?.text != null) {
      // The controller listener re-validates and rebuilds this card.
      widget.controller.text = data!.text!.trim();
    }
  }

  void _triggerInspect() {
    _onUrlChanged();
    final text = widget.controller.text.trim();
    final inspection = ref.read(inspectionProvider);
    if (_inlineUrlError == null && text.isNotEmpty && !inspection.isInspecting) {
      final uri = Uri.tryParse(text);
      if (uri != null) {
        ref.read(inspectionProvider.notifier).inspect(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInspecting = ref.watch(inspectionProvider.select((s) => s.isInspecting));
    final canInspect = _inlineUrlError == null && _hasText;
    final linkHelperText = _linkHelperText;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm8),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: widget.controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _triggerInspect(),
              style: AppTypography.body,
              decoration: InputDecoration(
                labelText: 'Download link',
                hintText: 'https://...',
                errorText: _inlineUrlError,
                errorMaxLines: 2,
                helperText: _inlineUrlError == null ? linkHelperText : null,
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  tooltip: 'Paste from clipboard',
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md12),
            if (isInspecting)
              SizedBox(
                height: AppSpacing.minTouchTarget,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: AppSpacing.md12),
                    Expanded(
                      child: Text(
                        'Checking link...',
                        style: AppTypography.metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm8),
                    OutlinedButton(
                      onPressed: () {
                        ref.read(inspectionProvider.notifier).cancel();
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              )
            else
              FilledButton(
                onPressed: canInspect ? _triggerInspect : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.manage_search_rounded, size: 20),
                    SizedBox(width: AppSpacing.sm8),
                    Flexible(child: Text('Inspect')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Slim "used / free" storage line under the downloads heading.
class _StorageStats extends StatelessWidget {
  final StorageInfo info;

  const _StorageStats({required this.info});

  @override
  Widget build(BuildContext context) {
    final usedMb = (info.usedBytes / (1024 * 1024)).toStringAsFixed(1);
    final freeGb = (info.freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return Semantics(
      container: true,
      label: 'Space used by downloads: $usedMb MB. Free space: $freeGb GB',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.lg16,
          runSpacing: AppSpacing.xs4,
          children: [
            _Stat(icon: Icons.download_done_rounded, value: '$usedMb MB', label: 'used'),
            _Stat(icon: Icons.sd_storage_outlined, value: '$freeGb GB', label: 'free'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xs4),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppTypography.tabularFigures.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' $label', style: AppTypography.metadata),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Small bordered note: tinted for warnings/errors, plain for information.
/// [dense] trims the vertical padding for a slim one-or-two-line note.
class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool tinted;
  final bool dense;

  const _Callout({
    required this.icon,
    required this.color,
    required this.text,
    this.tinted = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.md12, vertical: AppSpacing.sm8)
          : const EdgeInsets.all(AppSpacing.md12),
      decoration: BoxDecoration(
        color: tinted ? color.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        border: Border.all(color: tinted ? color.withValues(alpha: 0.35) : AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: dense ? 18 : 20, color: color),
          const SizedBox(width: AppSpacing.sm8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.metadata.copyWith(
                color: tinted ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slim "downloads keep running in the background" note, either right
/// under the storage line ([_BackgroundNoticeSliver.top]) or after the list
/// ([_BackgroundNoticeSliver.end]).
class _BackgroundNoticeSliver extends StatelessWidget {
  final bool atTop;

  const _BackgroundNoticeSliver.top()
      : atTop = true,
        super(key: const ValueKey('bg-notice-top'));

  const _BackgroundNoticeSliver.end()
      : atTop = false,
        super(key: const ValueKey('bg-notice-end'));

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: atTop
          ? const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.md12)
          : const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.lg16, 0),
      sliver: const SliverToBoxAdapter(
        child: _Callout(
          icon: Icons.info_outline_rounded,
          color: AppColors.primary,
          tinted: false,
          dense: true,
          text:
              'Downloads continue in the background. If you swipe MediaHub away from recent apps, they pause and resume when you reopen it.',
        ),
      ),
    );
  }
}

/// Icon tile + title + one metadata line, used at the top of result cards.
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _CardHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: AppSpacing.md12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppTypography.sectionTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: AppSpacing.xs4),
              Text(
                subtitle,
                style: AppTypography.metadata,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm8),
          trailing!,
        ],
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.metadata.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel {
  final String title;
  final int count;

  const _GroupLabel(this.title, this.count);

  /// Stable list key; prefixed so it never matches a task id key.
  Key get key => ValueKey<String>('h_$title');
}

/// "Completed  3" style label above each group of rows.
class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md12, bottom: AppSpacing.sm8),
      child: Semantics(
        header: true,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: title,
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: '  $count',
                style: AppTypography.label.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Icon-only row action; [emphasized] marks the main action of the row.
class _RowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool emphasized;

  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      style: emphasized
          ? IconButton.styleFrom(
              backgroundColor: AppColors.surfaceElevated,
              foregroundColor: AppColors.textPrimary,
            )
          : IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
    );
  }
}

/// One download: thumbnail with state badge, title, type/quality pills,
/// progress and the row actions. Watches only its own progress entry so a
/// running download does not rebuild the whole screen.
class _DownloadCard extends ConsumerWidget {
  final DownloadEntry task;
  final Widget actions;
  final VoidCallback? onTap;

  const _DownloadCard({
    required this.task,
    required this.actions,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(downloadProgressMapProvider.select((m) => m[task.id]));
    final isActive = _isActiveState(task.state);
    final isCompleted = task.state == DownloadTaskState.completed.name;
    final isPausedOrQueued = task.state == DownloadTaskState.paused.name ||
        task.state == DownloadTaskState.queued.name;

    int received = task.receivedBytes;
    int? total = task.totalBytes;
    double? speed;
    Duration? eta;

    if (isActive && update != null) {
      received = update.receivedBytes;
      total = update.totalBytes ?? total;
      speed = update.speedBytesPerSec;
      eta = update.eta;
    }

    final bool knownTotal = total != null && total > 0;
    final double progressVal = knownTotal ? (received / total).clamp(0.0, 1.0) : 0.0;

    final kind = _kindOf(task);
    final title = task.displayName.isNotEmpty ? task.displayName : task.fileName;
    final quality = task.qualityLabel;

    String sizeText;
    if (isCompleted) {
      sizeText = formatFileSize(task.receivedBytes > 0 ? task.receivedBytes : (total ?? 0));
    } else if (knownTotal) {
      final pct = (progressVal * 100).toStringAsFixed(0);
      sizeText = isActive || task.state == DownloadTaskState.paused.name
          ? '${formatFileSize(received)} / ${formatFileSize(total)} ($pct%)'
          : 'about ${formatFileSize(total)}';
    } else {
      sizeText = received > 0 ? '${formatFileSize(received)} / size unknown' : 'Size unknown';
    }

    final String? speedText = isActive && speed != null && speed > 0
        ? '${formatFileSize(speed.round())}/s'
            '${eta != null && eta.inSeconds > 0 ? " • ${_formatEta(eta)} left" : ""}'
        : null;

    // Progress bar (also while paused, so the user sees how far it got)
    final showProgress = isActive || (isPausedOrQueued && received > 0);
    final failedWithCode = task.state == DownloadTaskState.failed.name && task.errorCode != null;
    // Every state except "downloading" (which shows speed / ETA instead) keeps
    // its status line: Preparing..., Merging video and audio..., Paused, etc.
    final showStateText = !failedWithCode && task.state != DownloadTaskState.downloading.name;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DownloadThumb(task: task, kind: kind),
              const SizedBox(width: AppSpacing.md12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      breakableTitle(title),
                      semanticsLabel: title,
                      style: AppTypography.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs4),
                    Wrap(
                      spacing: AppSpacing.sm8,
                      runSpacing: AppSpacing.xs4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (kind != null)
                          PillTag(
                            text: kind == 'video' ? 'Video' : 'Audio',
                            icon: kind == 'video' ? Icons.videocam_rounded : Icons.music_note_rounded,
                            color: kind == 'video' ? AppColors.accent : AppColors.primary,
                          ),
                        if (quality != null && quality.isNotEmpty)
                          PillTag(text: quality, color: AppColors.textSecondary),
                        Text(
                          task.host,
                          style: AppTypography.metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: AppSpacing.md12),
            LinearProgressIndicator(
              value: knownTotal ? progressVal : (isActive ? null : 0),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              color: isActive ? AppColors.primary : AppColors.textMuted,
            ),
          ],
          const SizedBox(height: AppSpacing.sm8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.md12,
                      runSpacing: AppSpacing.xs4,
                      children: [
                        Text(sizeText, style: AppTypography.tabularFigures),
                        if (speedText != null)
                          Text(
                            speedText,
                            style: AppTypography.tabularFigures.copyWith(color: AppColors.textMuted),
                          ),
                      ],
                    ),
                    if (failedWithCode) ...[
                      const SizedBox(height: AppSpacing.xs4),
                      Text(
                        _formatPlainErrorMessage(task.errorCode!),
                        style: AppTypography.metadata.copyWith(color: AppColors.error),
                      ),
                      if (task.errorDetail != null && task.errorDetail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs4),
                          child: Text(
                            'Reason: ${task.errorDetail}',
                            style: AppTypography.caption,
                          ),
                        ),
                    ] else if (showStateText) ...[
                      const SizedBox(height: AppSpacing.xs4),
                      Text(
                        _formatStateText(task.state, task),
                        style: AppTypography.label.copyWith(
                          color: _stateTextColor(task.state),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm8),
              actions,
            ],
          ),
        ],
      ),
    );
  }
}

/// 64 dp rounded thumbnail with a state badge in the corner.
class _DownloadThumb extends StatelessWidget {
  final DownloadEntry task;
  final String? kind;

  static const double _size = 64;

  const _DownloadThumb({required this.task, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isVideo = kind == 'video';
    final placeholderIcon = isVideo ? Icons.movie_outlined : Icons.music_note_rounded;
    final placeholder = _ThumbPlaceholder(
      icon: placeholderIcon,
      color: isVideo ? AppColors.accent : AppColors.primary,
    );
    final thumb = task.thumbnailPath;
    final completed = task.state == DownloadTaskState.completed.name;

    Widget image;
    if (thumb != null) {
      image = Image.file(
        File(thumb),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        cacheWidth: 192,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (completed && task.finalPath != null) {
      // Direct downloads: embedded cover art / a video frame from the file itself.
      image = ArtworkThumbnail(
        uri: task.finalPath!,
        size: _size,
        borderRadius: 0,
        placeholderIcon: placeholderIcon,
      );
    } else {
      image = placeholder;
    }

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.md12),
            child: SizedBox(width: _size, height: _size, child: image),
          ),
          if (completed)
            Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
              ),
            ),
          Positioned(
            right: -AppSpacing.xs4,
            bottom: -AppSpacing.xs4,
            child: _StateBadge(state: task.state),
          ),
        ],
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _ThumbPlaceholder({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _DownloadThumb._size,
      height: _DownloadThumb._size,
      color: AppColors.surfaceElevated,
      child: Icon(icon, size: 28, color: color),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final String state;

  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _stateVisual(state);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

/// Static placeholder rows while the downloads list loads.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.surfacePressed,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
              child: SurfaceCard(
                padding: const EdgeInsets.all(AppSpacing.md12),
                child: Row(
                  children: [
                    Container(
                      width: _DownloadThumb._size,
                      height: _DownloadThumb._size,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppSpacing.md12),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(180, 14),
                          const SizedBox(height: AppSpacing.sm8),
                          bar(110, 12),
                          const SizedBox(height: AppSpacing.md12),
                          bar(double.infinity, 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
