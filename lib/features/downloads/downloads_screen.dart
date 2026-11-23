import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/downloads/ios_playable_formats.dart';
import '../../core/downloads/known_platform_checker.dart';
import '../../core/platform_info.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/url_policy.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../data/database/app_database.dart';
import '../../data/downloads/download_engine.dart' show DownloadEngine;
import '../../data/downloads/youtube_link.dart';
import '../../domain/models/download_state.dart';
import '../../domain/models/media_item.dart';
import '../../domain/repositories/platform_resolver.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../shared/widgets/ui_kit.dart';
import '../library/media_context_menu.dart' show isPathInside;
import '../music_player/playback_notifier.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/extractor_errors.dart';
import '../../personal/extractor_hosts.dart';
import '../../personal/personal_tools_notifier.dart';
import 'download_link_inbox.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';
import 'web_link_download_flow.dart';
import 'youtube_direct_flow.dart';
import '../library/playable.dart' show removeFromPlayQueue;
import 'mobile_data_guard.dart';

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

  /// The Saved group shows every saved download, not only the newest
  /// [kSavedPreviewCount]. Kept for as long as the app runs (the tab stays
  /// alive in the shell), never saved: the next start shows the short list.
  bool _showAllSaved = false;

  /// A quality lookup / quality sheet / queueing step is running.
  bool _linkFlowBusy = false;

  /// The link another tab (Online) handed over, noted above the field while
  /// the field still holds it.
  _HandedLink? _handedLink;
  bool _inboxCheckScheduled = false;

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

  void _onNotificationDenied() {
    if (mounted) setState(() => _notificationPermissionDenied = true);
  }

  // --- links handed over by other tabs (downloadLinkInboxProvider) ---------

  /// Takes the waiting link after this frame (providers must not change while
  /// the tree builds), and only while this tab is on screen: a link sent while
  /// Downloads is in the background waits in the inbox until the tab is shown.
  void _scheduleInboxCheck() {
    if (_inboxCheckScheduled) return;
    _inboxCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inboxCheckScheduled = false;
      if (!mounted) return;
      if (!TickerMode.getValuesNotifier(context).value.enabled) return;
      final link = ref.read(downloadLinkInboxProvider.notifier).take();
      if (link != null) _acceptHandedLink(link);
    });
  }

  /// Puts [link] in the field and, when asked, starts the same lookup the
  /// user gets by pasting it and tapping Choose quality / Inspect. While
  /// another lookup or quality choice is running the link only waits in the
  /// field (nothing is lost, nothing starts on top of the running one).
  void _acceptHandedLink(PendingDownloadLink link) {
    final text = link.url.trim();
    if (text.isEmpty) return;
    final busy = _linkFlowBusy || ref.read(inspectionProvider).isInspecting;
    _urlController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (!busy) _filenameController.clear();
    setState(() => _handedLink = _HandedLink(url: text, title: link.title, waiting: busy));
    if (busy || !link.inspect) return;
    // An invalid link stays in the field, which says what is wrong with it.
    if (!UrlPolicy.validate(text).isValid) return;
    final uri = Uri.parse(text);
    if (_opensQualityChoice(uri)) {
      _openQualityChoice(uri, titleHint: link.title);
    } else {
      ref.read(inspectionProvider.notifier).inspect(uri);
    }
  }

  // --- choosing a quality (yt-dlp, or YouTube without yt-dlp) --------------

  /// True when [uri] goes straight to the quality choice: a YouTube video
  /// (with or without yt-dlp), or any site yt-dlp handles while it is on.
  bool _opensQualityChoice(Uri uri) {
    if (YoutubeLink.parse(uri) != null) return true;
    return WebLinkDownloadFlow.isAvailable(ref) && KnownPlatformChecker.matchPlatformName(uri) != null;
  }

  /// Shows the link's card (Open link / Choose quality, so the choice can be
  /// reopened after the sheet is closed) and opens the quality choice.
  void _openQualityChoice(Uri uri, {String? titleHint}) {
    ref.read(inspectionProvider.notifier).inspect(uri);
    _chooseQuality(uri, titleHint: titleHint);
  }

  /// The quality choice for [uri]: yt-dlp (every quality) when it is on,
  /// otherwise, for YouTube, the files YouTube serves directly. On Android a
  /// YouTube link also falls back to that path when yt-dlp cannot run.
  Future<void> _chooseQuality(Uri uri, {String? titleHint}) async {
    if (_linkFlowBusy) return;
    final youtube = YoutubeLink.parse(uri);
    final ytdlp = WebLinkDownloadFlow.isAvailable(ref);
    if (!ytdlp && youtube == null) return;

    final fieldAtStart = _urlController.text.trim();
    void queued() => _afterQueued(fieldAtStart);
    final handed = _handedLink;
    setState(() {
      _linkFlowBusy = true;
      if (handed != null && handed.waiting && handed.url == fieldAtStart) {
        _handedLink = _HandedLink(url: handed.url, title: handed.title);
      }
    });
    try {
      if (ytdlp) {
        await WebLinkDownloadFlow.start(
          context,
          ref,
          uri,
          onQueued: queued,
          onNotificationDenied: _onNotificationDenied,
          onEngineUnavailable: youtube == null
              ? null
              : () => _startYoutubeDirect(youtube, titleHint: titleHint, onQueued: queued),
          // A site yt-dlp does not read: the direct-file check instead.
          onOtherSite: () async => ref.read(inspectionProvider.notifier).inspect(uri),
          onRetry: () => _retryQuality(uri, titleHint: titleHint),
        );
      } else {
        await _startYoutubeDirect(youtube!, titleHint: titleHint, onQueued: queued);
      }
    } finally {
      if (mounted) setState(() => _linkFlowBusy = false);
    }
  }

  Future<void> _startYoutubeDirect(YoutubeLink link, {String? titleHint, required VoidCallback onQueued}) async {
    if (!mounted) return;
    await YoutubeDirectDownloadFlow.start(
      context,
      ref,
      link,
      titleHint: titleHint ?? _titleHintFor(link),
      onQueued: onQueued,
      onNotificationDenied: _onNotificationDenied,
      onRetry: () => _retryQuality(Uri.parse(link.canonicalUrl), titleHint: titleHint),
    );
  }

  /// Retry on a failed quality lookup's message.
  void _retryQuality(Uri uri, {String? titleHint}) {
    if (mounted) unawaited(_chooseQuality(uri, titleHint: titleHint));
  }

  /// The title the Online tab sent with [link], if that is the link in hand.
  String? _titleHintFor(YoutubeLink link) {
    final handed = _handedLink;
    if (handed == null) return null;
    return YoutubeLink.tryParse(handed.url)?.videoId == link.videoId ? handed.title : null;
  }

  /// After a download was queued: clears the field and the link card, unless
  /// the field changed meanwhile (e.g. another link arrived from Online while
  /// the quality sheet was open), so that link is never lost.
  void _afterQueued(String fieldAtStart) {
    if (!mounted) return;
    final current = _urlController.text.trim();
    if (current == fieldAtStart) {
      _urlController.clear();
      _filenameController.clear();
      ref.read(inspectionProvider.notifier).clear();
      return;
    }
    final inspected = ref.read(inspectionProvider).result?.uri;
    if (inspected != null && inspected != Uri.tryParse(current)) {
      ref.read(inspectionProvider.notifier).clear();
    }
  }

  /// "Choose quality" (and on Android with yt-dlp off, "Enable downloader")
  /// shown next to "Open link". Empty when nothing can download [uri].
  List<Widget> _qualityActions(Uri uri) {
    final ytdlpSupported = PlatformInfo.supportsWebLinkDownloader && kPersonalToolsEnabled;
    final ytdlpOn = ytdlpSupported && ref.watch(personalToolsProvider).isEnabled;
    final youtube = YoutubeLink.parse(uri) != null;
    // yt-dlp only reads its own list of sites: on any other page "Choose
    // quality" could only end in "not supported".
    return [
      if (youtube || (ytdlpOn && ExtractorHosts.isAllowed(uri)))
        FilledButton.icon(
          icon: const Icon(Icons.video_library_rounded),
          label: const Text('Choose quality'),
          onPressed: _linkFlowBusy ? null : () => _chooseQuality(uri),
        ),
      if (ytdlpSupported && !ytdlpOn)
        TextButton.icon(
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Enable downloader'),
          onPressed: () => context.push('/settings'),
        ),
    ];
  }

  Future<void> _startDownload(SourceInfo info) async {
    final fieldAtStart = _urlController.text.trim();
    await _ensureNotificationPermission();

    if (!mounted) return;
    if (await WebLinkDownloadFlow.confirmNotice(context, ref)) {
      if (!mounted || !await confirmBigDownloadOnMobileData(context, ref, info.contentLength)) return;
      if (!mounted) return;
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

      _afterQueued(fieldAtStart);

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

    // A link handed over by another tab: taken on the first build and
    // whenever a new one arrives, once this tab is on screen (an inactive
    // shell branch has tickers off, and turning them on rebuilds this).
    final linkWaiting = ref.watch(downloadLinkInboxProvider.select((link) => link != null));
    if (linkWaiting && TickerMode.valuesOf(context).enabled) _scheduleInboxCheck();
    // A waiting handed-over link stops "waiting" once the user inspects it.
    ref.listen(inspectionProvider.select((s) => s.isInspecting), (_, inspecting) {
      final handed = _handedLink;
      if (inspecting && handed != null && handed.waiting && _urlController.text.trim() == handed.url) {
        setState(() => _handedLink = _HandedLink(url: handed.url, title: handed.title));
      }
    });

    // The masthead summary ("3 ACTIVE · 1.2 GB FREE").
    final all = downloadsAsync.asData?.value ?? const <DownloadEntry>[];
    final activeCount = all.where((t) => _isActiveState(t.state)).length;
    final savedCount = all.where((t) => t.state == DownloadTaskState.completed.name).length;

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
                  _Header(
                    active: activeCount,
                    saved: savedCount,
                    freeBytes: storageAsync.asData?.value.freeBytes,
                    // The paste-link field is the hero's main element.
                    child: _UrlCard(
                      controller: _urlController,
                      handedLink: _handedLink,
                      busy: _linkFlowBusy,
                      onChooseQuality: (uri) => _openQualityChoice(uri),
                    ),
                  ),
                  if (inspection.errorMessage != null && !inspection.isInspecting) ...[
                    const SizedBox(height: AppSpacing.md12),
                    _Callout(
                      icon: Icons.error_outline_rounded,
                      tone: _Tone.error,
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
                      icon: Icons.notifications_off_rounded,
                      tone: _Tone.warning,
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
    return Wrap(
      spacing: AppSpacing.sm8,
      runSpacing: AppSpacing.sm8,
      children: [
        _openLinkButton(uri),
        ..._qualityActions(uri),
      ],
    );
  }

  /// The note on a known platform's card: what can be done with the link here.
  String _platformNote(String platform, Uri uri, {required bool ytdlpOn}) {
    if (ytdlpOn) {
      return '$platform link detected. Tap "Choose quality" to download the public video or audio. Only save content you have the right to download.';
    }
    final youtube = YoutubeLink.check(uri);
    if (youtube.link != null) {
      final more = PlatformInfo.supportsWebLinkDownloader && kPersonalToolsEnabled
          ? ' For every quality up to 4K, turn on "Enable web link downloader" in Settings.'
          : '';
      return '$platform link detected. Tap "Choose quality" to save the video or just its audio. Only save content you have the right to download.$more';
    }
    if (youtube.isCollection) {
      return "Playlists and channels can't be downloaded. Open a single video and copy its link.";
    }
    // iPhone has no web link downloader (and no such setting): say what does work there.
    if (PlatformInfo.isIOS) return iosPlatformNote(platform);
    return '$platform pages are not direct media files. Turn on "Enable web link downloader" in Settings to download public videos, or open the link in the $platform app.';
  }

  Widget _buildInspectionResultCard(SourceInfo info) {
    final inspection = ref.watch(inspectionProvider);
    final knownPlatform = inspection.knownPlatformName;
    final downloaderEnabled = PlatformInfo.supportsWebLinkDownloader &&
        kPersonalToolsEnabled &&
        ref.watch(personalToolsProvider).isEnabled;

    if (knownPlatform != null) {
      final canDownload = downloaderEnabled || YoutubeLink.parse(info.uri) != null;
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              icon: Icons.public_rounded,
              tone: canDownload ? _Tone.brand : _Tone.warning,
              title: 'Platform Link',
              subtitle: 'Host: ${info.uri.host}',
              trailing: PillTag(text: knownPlatform),
            ),
            const SizedBox(height: AppSpacing.lg16),
            _Callout(
              icon: canDownload ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
              tone: canDownload ? _Tone.brand : _Tone.warning,
              text: _platformNote(knownPlatform, info.uri, ytdlpOn: downloaderEnabled),
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

    // Said up front: a file over the 2 GB limit would only fail later.
    final tooBig = isDownloadable &&
        info.contentLength != null &&
        info.contentLength! > DownloadEngine.maxDownloadSizeBytes;

    // iPhone cannot play some kinds of file (WebM, MKV, Ogg, Opus, AVI): such
    // a link is refused here instead of saving a file that never plays.
    final iosUnplayable = PlatformInfo.isIOS && isDownloadable
        ? IosPlayableFormats.unplayableFormat(
            mimeType: info.contentType,
            fileName: info.suggestedFilename ??
                (info.uri.pathSegments.isNotEmpty ? info.uri.pathSegments.last : null),
          )
        : null;

    if (_filenameController.text.isEmpty && info.suggestedFilename != null) {
      _filenameController.text = info.suggestedFilename!;
    }

    final contentType = info.contentType ?? '';
    final IconData headerIcon;
    final _Tone headerTone;
    if (isWebPage || iosUnplayable != null || tooBig) {
      headerIcon = isWebPage ? Icons.language_rounded : Icons.block_rounded;
      headerTone = _Tone.warning;
    } else if (!isDownloadable) {
      headerIcon = Icons.link_off_rounded;
      headerTone = _Tone.error;
    } else if (contentType.startsWith('video')) {
      headerIcon = Icons.video_file_rounded;
      headerTone = _Tone.accent;
    } else if (contentType.startsWith('audio')) {
      headerIcon = Icons.audio_file_rounded;
      headerTone = _Tone.brand;
    } else {
      headerIcon = Icons.insert_drive_file_rounded;
      headerTone = _Tone.brand;
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: headerIcon,
            tone: headerTone,
            title: 'Inspection Result',
            subtitle: 'Host: ${info.uri.host}',
          ),
          const SizedBox(height: AppSpacing.sm8),
          _DetailLine(
            icon: Icons.description_rounded,
            text: 'Content Type: ${info.contentType ?? "Unknown"}',
          ),
          _DetailLine(
            icon: Icons.data_usage_rounded,
            text: 'Size: ',
            figure: info.contentLength != null
                ? '${(info.contentLength! / (1024 * 1024)).toStringAsFixed(2)} MB'
                : null,
            fallback: 'Unknown size',
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
              tone: _Tone.warning,
              text:
                  'This is a web page, not a media file. MediaHub can only download direct media files that you have the right to save.',
            ),
            const SizedBox(height: AppSpacing.md12),
            _linkActions(info.uri),
          ] else if (!isDownloadable) ...[
            _Callout(
              icon: Icons.block_rounded,
              tone: _Tone.error,
              text: info.humanReadableReason ??
                  'This link cannot be downloaded as it is not a direct media file.',
            ),
          ] else if (iosUnplayable != null) ...[
            _Callout(
              icon: Icons.warning_amber_rounded,
              tone: _Tone.warning,
              text: IosPlayableFormats.refusal(iosUnplayable),
            ),
          ] else if (tooBig) ...[
            const _Callout(
              icon: Icons.warning_amber_rounded,
              tone: _Tone.warning,
              text: tooBigToSaveText,
            ),
          ] else ...[
            TextField(
              controller: _filenameController,
              style: context.typography.body,
              decoration: const InputDecoration(
                labelText: 'File name',
                prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md12),
            // The "get" action is the Volt button (DESIGN.md 7.2).
            VoltButton(
              expand: true,
              icon: Icons.download_rounded,
              label: 'Download',
              onPressed: () => _startDownload(info),
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

    final completed = newestSavedFirst(tasks.where((t) =>
        t.state == DownloadTaskState.completed.name));

    final failed = tasks.where((t) =>
        t.state == DownloadTaskState.failed.name ||
        t.state == DownloadTaskState.cancelled.name).toList();

    // Flattened list of group labels and rows, built lazily below. Every item
    // is keyed and indexed so a row that moves (Active -> Completed) keeps its
    // element and state instead of rebuilding every card below it.
    final rows = <Object>[];
    final indexByKey = <Key, int>{};
    void addLabel(String title, int count) {
      final label = _GroupLabel(title, count);
      indexByKey[label.key] = rows.length;
      rows.add(label);
    }

    void addTasks(Iterable<DownloadEntry> group) {
      for (final task in group) {
        indexByKey[ValueKey<String>(task.id)] = rows.length;
        rows.add(task);
      }
    }

    void addGroup(String title, List<DownloadEntry> group) {
      if (group.isEmpty) return;
      addLabel(title, group.length);
      addTasks(group);
    }

    // Everything that needs the user (running, waiting, paused, failed) always
    // shows. Saved files are also in Videos and Music, so the Saved group
    // shows only the newest few; the rest open in place, and the toggle
    // ("Show less") then ends the whole Saved list.
    addGroup('Active', active);
    addGroup('Queued / Paused', queuedOrPaused);
    if (completed.isNotEmpty) {
      addLabel('Saved', completed.length);
      addTasks(completed.take(kSavedPreviewCount));
      if (completed.length > kSavedPreviewCount) {
        if (_showAllSaved) addTasks(completed.skip(kSavedPreviewCount));
        indexByKey[_SavedToggleRow.key] = rows.length;
        rows.add(_SavedToggleRow(total: completed.length, expanded: _showAllSaved));
      }
    }
    addGroup('Failed / Cancelled', failed);

    final isVideoFilter = _kindFilter == 'video';

    return [
      if (hasInProgress) const _BackgroundNoticeSliver.top(),
      SliverPadding(
        key: const ValueKey('kind-filter'),
        // The chip row scrolls edge to edge with its own 16 dp gutters.
        padding: EdgeInsets.zero,
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
            if (row is _SavedToggleRow) {
              return _SavedToggle(
                key: _SavedToggleRow.key,
                total: row.total,
                expanded: row.expanded,
                onPressed: () => setState(() => _showAllSaved = !_showAllSaved),
              );
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
    final palette = context.palette;
    // Fill, label, edge and check come from the chip theme (DESIGN.md 7.3):
    // selected is the Volt sticker with an ink label and ink check.
    Widget chip(String label, String? value, IconData icon) {
      final selected = _kindFilter == value;
      return ChoiceChip(
        key: ValueKey('downloads_kind_${value ?? 'all'}'),
        // Selected shows only the ink check; the kind glyph would sit muddy
        // under it on the Volt fill.
        avatar: selected ? null : Icon(icon, size: 16, color: palette.textSecondary),
        label: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              TextSpan(
                text: '  ${counts[value] ?? 0}',
                // The count in DM Mono; selected keeps the label's own ink
                // (from the chip theme).
                style: TextStyle(
                  fontFamily: AppTypography.dmMono,
                  fontFamilyFallback: AppTypography.readingFallback,
                  color: selected ? null : palette.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        selected: selected,
        onSelected: (_) => setState(() => _kindFilter = value),
      );
    }

    // DESIGN.md 7.3: a filter row scrolls sideways with 16 dp gutters, so
    // large text never pushes a chip onto a second line.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.xs4),
      child: Row(
        children: [
          chip('All', null, Icons.apps_rounded),
          const SizedBox(width: AppSpacing.sm8),
          chip('Video', 'video', Icons.videocam_rounded),
          const SizedBox(width: AppSpacing.sm8),
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
          // DESIGN.md 7.14: Failed shows a Retry text button.
          TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
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
    // gone, and the screen can go away while the dialog is open. With all of
    // them captured here a confirmed delete still completes.
    final db = ref.read(appDatabaseProvider);
    final library = ref.read(libraryRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    // Marked handled at once: a folder that cannot be found only means no
    // file is deleted.
    final downloadDir = ref.read(downloadDirectoryProvider.future)..ignore();
    final runner = task.engine == 'extractor' ? ref.read(extractorDownloadRunnerProvider) : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: ctx.palette.error),
        title: const Text('Delete download?'),
        content: Text(
          'Delete "${breakableTitle(task.fileName)}"? Your other files are safe.',
          semanticsLabel: 'Delete "${task.fileName}"? Your other files are safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          // A destructive confirm is a text button in error (DESIGN.md 7.10).
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ctx.palette.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Delete files on disk if they exist (media + cover image), and only
      // inside the downloads folder: a row pointing anywhere else (a corrupt
      // or crafted database) never deletes that file.
      final paths = [task.finalPath, task.thumbnailPath].whereType<String>().toList();
      String? dir;
      if (paths.isNotEmpty) {
        try {
          dir = (await downloadDir).path;
        } catch (_) {}
      }
      for (final path in paths) {
        if (dir == null || !isPathInside(dir, path)) continue;
        final f = File(path);
        if (f.existsSync()) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }

      // The song leaves the library with everything pointing at it: its
      // playlist entries (each playlist renumbered, so its count, remove and
      // reorder stay right), its video progress, its row, and the queue.
      final mediaId = task.mediaId;
      if (mediaId != null) {
        await library.deleteMediaCompletely(mediaId);
        try {
          await removeFromPlayQueue(container, mediaId);
        } catch (_) {}
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
    // No library row: the row's kind decides (set from the file's own tracks
    // when it finished), then its type, the same as the Videos / Music chips.
    item ??= MediaItem(
      id: task.mediaId ?? 'dl_${task.id}',
      uri: task.finalPath!,
      mediaType: _kindOf(task) == 'video' ? MediaType.video : MediaType.audio,
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
    final playback = ref.read(playbackNotifierProvider.notifier);
    if (index < 0) {
      playback.loadQueue([item], autoPlay: true, shuffle: playback.shuffleMode);
    } else {
      // Shuffle mode stays as the user set it: the tapped song first.
      playback.loadQueue(queue, startIndex: index, autoPlay: true, shuffle: playback.shuffleMode);
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

/// How many saved downloads the Saved group shows before its "Show all"
/// toggle (for the chosen kind chip). Every saved file is also listed in
/// Videos or Music, so the Downloads tab needs only the latest few.
@visibleForTesting
const int kSavedPreviewCount = 5;

/// [saved] newest first by when each one finished: a saved row's
/// `updatedAt` is written when it completes and not after. A download that
/// was started long ago and finished just now is then among the first ones,
/// never hidden behind "Show all". Ties go by when it was added, then id, so
/// the order never shuffles between rebuilds.
@visibleForTesting
List<DownloadEntry> newestSavedFirst(Iterable<DownloadEntry> saved) {
  return saved.toList()
    ..sort((a, b) {
      final finished = b.updatedAt.compareTo(a.updatedAt);
      if (finished != 0) return finished;
      final added = b.createdAt.compareTo(a.createdAt);
      if (added != 0) return added;
      return b.id.compareTo(a.id);
    });
}

/// The colour role of a note, a tile glyph or a row state, resolved against
/// the theme's palette by [_toneColor] (so the widgets using it stay const).
enum _Tone { brand, accent, warning, error, success, secondary, muted }

Color _toneColor(AppPalette p, _Tone tone) => switch (tone) {
      _Tone.brand => p.primary,
      _Tone.accent => p.accent,
      _Tone.warning => p.warning,
      _Tone.error => p.error,
      _Tone.success => p.success,
      _Tone.secondary => p.textSecondary,
      _Tone.muted => p.textMuted,
    };

/// Icon and tone of a row's state line: always an icon and a word, never
/// colour alone (DESIGN.md 7.14).
(IconData, _Tone) _stateVisual(String state) {
  if (state == DownloadTaskState.completed.name) return (Icons.check_circle_rounded, _Tone.success);
  if (_isActiveState(state)) return (Icons.downloading_rounded, _Tone.brand);
  if (state == DownloadTaskState.paused.name) return (Icons.pause_circle_rounded, _Tone.secondary);
  if (state == DownloadTaskState.failed.name) return (Icons.error_rounded, _Tone.error);
  if (state == DownloadTaskState.cancelled.name) return (Icons.cancel_rounded, _Tone.muted);
  return (Icons.schedule_rounded, _Tone.warning);
}

/// Room a download row's actions take at most (two 48 dp buttons and the
/// 8 dp gap before them).
const double _kRowActionsWidth = 104 + AppSpacing.sm8;

/// Below this width (at 1.0x text, scaled with the text) the figures leave
/// the actions' side and take a line of their own.
const double _kMinFiguresWidth = 150;

/// No-break space: keeps a figure and its unit on one line ("412.0 MB").
const String _nbsp = ' ';

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
      return 'Saved';
    case 'cancelled':
      return 'Cancelled';
    case 'failed':
      return 'Failed';
    default:
      return state;
  }
}

/// The link card's note for a file over the 2 GB limit (no Download button).
@visibleForTesting
const String tooBigToSaveText = 'This file is bigger than 2 GB, the most MediaHub can save.';

/// The Platform Link card's note on iPhone for a site other than YouTube:
/// there is no web link downloader there, so only two kinds of link work.
@visibleForTesting
String iosPlatformNote(String platform) =>
    "$platform links can't be saved on iPhone. Only YouTube videos and direct links to audio or video "
    'files can be saved here. You can still open the link in the $platform app.';

/// Plain words for a failed download's [errorCode]: what happened, in one
/// short sentence, and what to do (the row's Retry button, or another link).
/// [host] is the server the file came from (YouTube's links to its files
/// stop working after some hours).
@visibleForTesting
String formatPlainErrorMessage(String errorCode, {String host = ''}) {
  if ((errorCode == 'http_403' || errorCode == 'http_410') && YoutubeLink.isYoutubeMediaHost(host)) {
    // iPhone looks the link up again by itself on a resume or retry, so it
    // only lands here when that failed too (offline, or the video is gone).
    if (PlatformInfo.isIOS) {
      return "YouTube's link to this file has expired and a new one could not be found. "
          'Tap Retry, or paste the video link again.';
    }
    return "YouTube's link to this file has expired. Paste the video link again to download it.";
  }
  // The web link downloader's own failures: its words (they know every
  // code it reports, and that it already updated itself and tried again).
  if (errorCode.startsWith('x_')) return ExtractorErrors.downloadMessage(errorCode);
  const retryLater = "Couldn't reach the website. Check your connection, then tap Retry.";
  const tooBig = tooBigToSaveText;
  switch (errorCode) {
    case 'insufficient_disk_space':
      // A real "disk full" while writing (the iPhone has no space check up front).
      if (PlatformInfo.isIOS) {
        return 'Your iPhone is full. Free up some space, then tap Retry. Your other files are safe.';
      }
      return 'Your phone is out of space. Free up some space, then tap Retry.';
    case IosPlayableFormats.errorCode:
      return IosPlayableFormats.refusedAfterDownload;
    case 'write_failed':
      return "Couldn't save the file on your phone. Tap Retry.";
    case 'incomplete_download':
      return 'The connection dropped before the end. Tap Retry to carry on.';
    case 'not_media':
      return "This link isn't a music or video file. Check the link.";
    case 'max_size_exceeded':
    case 'max_body_size_exceeded':
      return tooBig;
    case 'content_range_mismatch':
    case 'size_mismatch':
      return "The file didn't arrive complete. Tap Retry.";
    case 'connection_error':
    case 'dns_resolution_failed':
    case 'dns_no_addresses':
      return retryLater;
    case 'blocked_ip':
    case 'blockedIpLiteral':
      return "This link points to a private network, which MediaHub doesn't allow.";
    case 'too_many_redirects':
    case 'missing_redirect_location':
    case 'invalid_redirect_uri':
      return 'This link keeps sending MediaHub somewhere else. Check the link.';
    case 'http_401':
      return "This needs a login, so it can't be saved. Only public files can.";
    case 'http_403':
      return 'The website refused the download. Check the link, then tap Retry.';
    case 'http_404':
    case 'http_410':
      return "The file isn't at this link any more. It may have been removed.";
    case 'http_429':
      return 'The website is busy. Wait a minute, then tap Retry.';
    default:
      if (errorCode.startsWith('http_5')) return 'The website had a problem. Tap Retry later.';
      if (errorCode.startsWith('http_')) {
        return 'The website answered with error ${errorCode.replaceFirst('http_', '')}. Tap Retry.';
      }
      return "This download didn't work. Check your connection, then tap Retry.";
  }
}

/// A link another tab handed to Downloads (see [DownloadLinkInbox]).
class _HandedLink {
  const _HandedLink({required this.url, this.title, this.waiting = false});

  final String url;
  final String? title;

  /// It arrived while another lookup or quality choice was running, so it
  /// waits in the field until the user starts it.
  final bool waiting;
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// The tab masthead (DESIGN.md 7.14): "Downloads" in the display role and an
/// overline summary such as "3 ACTIVE · 1.2 GB FREE".
class _Header extends StatelessWidget {
  /// Downloads running now (preparing, downloading or finalizing).
  final int active;

  /// Finished downloads, shown in the summary while nothing is running.
  final int saved;

  /// Free space on the phone; null until it is known.
  final int? freeBytes;

  /// The link field and its action, inside the hero.
  final Widget? child;

  const _Header({required this.active, required this.saved, this.freeBytes, this.child});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final free = freeBytes == null ? null : formatFileSize(freeBytes!);
    final count = active > 0
        ? (active, 'active')
        : saved > 0
            ? (saved, 'saved')
            : null;
    final shown = [
      if (count != null) '${count.$1} ${count.$2.toUpperCase()}',
      if (free != null) '${free.toUpperCase()} FREE',
    ];
    final spoken = [
      if (count != null) '${count.$1} ${count.$2} ${count.$1 == 1 ? 'download' : 'downloads'}',
      if (free != null) '$free free',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md12, bottom: AppSpacing.lg16),
      child: EntranceFade(
        child: HeroBand(
          glow: true,
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SparkMark(height: 4),
          const SizedBox(height: AppSpacing.md12),
          // One line, scaled down rather than clipped at large text sizes.
          Semantics(
            header: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text('Downloads', style: type.display, maxLines: 1),
            ),
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs4),
            Text(
              shown.join(' · '),
              semanticsLabel: spoken.join(', '),
              style: type.overline.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
          if (child != null) ...[
            const SizedBox(height: AppSpacing.md12),
            child!,
          ],
        ],
          ),
        ),
      ),
    );
  }
}

/// The link field (a stadium, with paste) and the main action under it.
///
/// Keeps its own validation state and listens to [controller] itself, so a
/// keystroke rebuilds only this card (and only when the error or the empty /
/// non-empty state actually changes), never the download list below.
class _UrlCard extends ConsumerStatefulWidget {
  final TextEditingController controller;

  /// The link another tab handed over (noted while the field still holds it).
  final _HandedLink? handedLink;

  /// A quality lookup or choice is running: the main button waits.
  final bool busy;

  /// "Choose quality" for a YouTube link in the field.
  final void Function(Uri uri) onChooseQuality;

  const _UrlCard({
    required this.controller,
    required this.onChooseQuality,
    this.handedLink,
    this.busy = false,
  });

  @override
  ConsumerState<_UrlCard> createState() => _UrlCardState();
}

class _UrlCardState extends ConsumerState<_UrlCard> {
  String? _inlineUrlError;
  bool _hasText = false;

  /// The field holds a valid link to one YouTube video.
  bool _isYoutubeVideo = false;

  /// The field still holds the link from [_UrlCard.handedLink].
  bool _holdsHandedLink = false;

  /// Android bundles yt-dlp, so YouTube, Instagram and other supported sites
  /// can be downloaded there while "Enable web link downloader" is on (the
  /// same rule as the inspection card). YouTube videos work everywhere: without
  /// yt-dlp (iOS, or the setting off) through the files YouTube serves
  /// directly. Called from [build]: it watches only the on / off flag, so a
  /// keystroke still rebuilds nothing else.
  String get _linkHelperText {
    if (_isYoutubeVideo) {
      return 'YouTube link: supported. Tap Choose quality to save the video or just its audio';
    }
    final downloaderEnabled = PlatformInfo.supportsWebLinkDownloader &&
        kPersonalToolsEnabled &&
        ref.watch(personalToolsProvider.select((s) => s.isEnabled));
    return downloaderEnabled
        ? 'Paste a YouTube, Instagram or direct https link'
        : 'Paste a YouTube link, or a direct https link to audio or video';
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
    }
    _syncFromText();
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
    final isYoutube = error == null && hasText && YoutubeLink.tryParse(text) != null;
    final holdsHanded = hasText && widget.handedLink?.url == text;
    if (error == _inlineUrlError &&
        hasText == _hasText &&
        isYoutube == _isYoutubeVideo &&
        holdsHanded == _holdsHandedLink) {
      return false;
    }
    _inlineUrlError = error;
    _hasText = hasText;
    _isYoutubeVideo = isYoutube;
    _holdsHandedLink = holdsHanded;
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

  /// The main button / Done key: Choose quality for a YouTube video, else Inspect.
  void _triggerMainAction() {
    _onUrlChanged();
    if (!_isYoutubeVideo) {
      _triggerInspect();
      return;
    }
    if (widget.busy || ref.read(inspectionProvider).isInspecting) return;
    final uri = Uri.tryParse(widget.controller.text.trim());
    if (uri != null) widget.onChooseQuality(uri);
  }

  /// "Link from Online", or how to go on when it arrived during another choice.
  String _handedLinkNote(_HandedLink link) {
    final title = link.title?.trim() ?? '';
    if (link.waiting) {
      final action = _isYoutubeVideo ? 'Choose quality' : 'Inspect';
      return 'Link from Online is ready${title.isEmpty ? '' : ': $title'}. '
          'When the current download choice is done, tap $action.';
    }
    return title.isEmpty ? 'Link from Online' : 'Link from Online: $title';
  }

  @override
  Widget build(BuildContext context) {
    final isInspecting = ref.watch(inspectionProvider.select((s) => s.isInspecting));
    final canInspect = _inlineUrlError == null && _hasText;
    final linkHelperText = _linkHelperText;
    final handed = _holdsHandedLink ? widget.handedLink : null;
    final type = context.typography;

    // The search-style stadium (DESIGN.md 7.11 / 7.14): the theme's fill,
    // outline and focus ring on a stadium instead of the 16 dp form radius.
    final fieldTheme = Theme.of(context).inputDecorationTheme;
    InputBorder? stadium(InputBorder? border) => border is OutlineInputBorder
        ? border.copyWith(borderRadius: const BorderRadius.all(Radius.circular(AppSpacing.huge48)))
        : border;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _triggerMainAction(),
            style: type.body,
            decoration: InputDecoration(
              labelText: 'Download link',
              // A label floating on a stadium's curved edge would be cut by
              // it: "Download link" stays the placeholder (and the field's
              // name for screen readers).
              floatingLabelBehavior: FloatingLabelBehavior.never,
              labelStyle: type.body.copyWith(color: context.palette.textMuted),
              hintText: 'https://...',
              errorText: _inlineUrlError,
              errorMaxLines: 2,
              helperText: _inlineUrlError == null ? linkHelperText : null,
              helperMaxLines: 2,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.md12),
              prefixIcon: const Padding(
                padding: EdgeInsetsDirectional.only(start: AppSpacing.xs4),
                child: Icon(Icons.link_rounded),
              ),
              suffixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs4),
                child: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  tooltip: 'Paste from clipboard',
                  onPressed: _pasteFromClipboard,
                ),
              ),
              border: stadium(fieldTheme.border),
              enabledBorder: stadium(fieldTheme.enabledBorder),
              disabledBorder: stadium(fieldTheme.disabledBorder),
              focusedBorder: stadium(fieldTheme.focusedBorder),
              errorBorder: stadium(fieldTheme.errorBorder),
              focusedErrorBorder: stadium(fieldTheme.focusedErrorBorder),
            ),
          ),
          if (handed != null) ...[
            const SizedBox(height: AppSpacing.md12),
            Semantics(
              liveRegion: true,
              child: _Callout(
                icon: handed.waiting ? Icons.schedule_rounded : Icons.input_rounded,
                tone: _Tone.accent,
                tinted: false,
                dense: true,
                text: _handedLinkNote(handed),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md12),
          if (isInspecting)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: VoltButton.height),
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.xs4),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: Text(
                      'Checking link...',
                      style: type.metadata,
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
            // The one loud action of the screen (DESIGN.md 7.14): full width
            // under the field. It names the next step: the quality choice for
            // a YouTube video, a check of any other link (whose card then
            // offers Download).
            VoltButton(
              expand: true,
              icon: _isYoutubeVideo ? Icons.download_rounded : Icons.manage_search_rounded,
              label: _isYoutubeVideo ? 'Choose quality' : 'Inspect',
              onPressed: canInspect && !(_isYoutubeVideo && widget.busy) ? _triggerMainAction : null,
            ),
        ],
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
    // No free figure when the phone cannot tell (iOS).
    final free = info.freeBytes;
    final freeGb = free == null ? null : (free / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return Semantics(
      container: true,
      label: freeGb == null
          ? 'Space used by downloads: $usedMb MB'
          : 'Space used by downloads: $usedMb MB. Free space: $freeGb GB',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.lg16,
          runSpacing: AppSpacing.xs4,
          children: [
            _Stat(icon: Icons.download_done_rounded, value: '$usedMb MB', label: 'used'),
            if (freeGb != null) _Stat(icon: Icons.sd_storage_rounded, value: '$freeGb GB', label: 'free'),
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
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: palette.textMuted),
        const SizedBox(width: AppSpacing.xs4),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                // Figures in DM Mono at 14 inside the metadata line.
                TextSpan(
                  text: value,
                  style: type.tabularFigures.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    color: palette.textPrimary,
                  ),
                ),
                TextSpan(text: ' $label', style: type.metadata),
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

/// Small note: tinted for warnings and errors, plain for information.
/// [dense] trims the vertical padding for a slim one-or-two-line note.
class _Callout extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String text;
  final bool tinted;
  final bool dense;

  const _Callout({
    required this.icon,
    required this.tone,
    required this.text,
    this.tinted = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final color = _toneColor(palette, tone);
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.md12, vertical: AppSpacing.sm8)
          : const EdgeInsets.all(AppSpacing.md12),
      decoration: BoxDecoration(
        color: tinted ? color.withValues(alpha: 0.08) : palette.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
        border: Border.all(color: tinted ? color.withValues(alpha: 0.35) : palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: dense ? 18 : 20, color: color),
          const SizedBox(width: AppSpacing.sm8),
          Expanded(
            child: Text(
              text,
              style: type.metadata.copyWith(
                color: tinted ? palette.textPrimary : palette.textSecondary,
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
      sliver: SliverToBoxAdapter(
        child: _Callout(
          icon: Icons.info_outline_rounded,
          tone: _Tone.brand,
          tinted: false,
          dense: true,
          // iOS gives an app no background downloads of this kind.
          text: PlatformInfo.isIOS
              ? 'Keep MediaHub open until downloads finish.'
              : 'Downloads continue in the background. If you swipe MediaHub away from recent apps, they pause and resume when you reopen it.',
        ),
      ),
    );
  }
}

/// Tonal tile ([AppPalette.primaryContainer], radius 14) holding a glyph:
/// the leading tile of result cards and of rows without a cover.
class _TypeTile extends StatelessWidget {
  final IconData icon;
  final _Tone tone;

  const _TypeTile({required this.icon, required this.tone});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: _DownloadThumb.size,
      height: _DownloadThumb.size,
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
      ),
      child: Icon(icon, size: 24, color: _toneColor(palette, tone)),
    );
  }
}

/// Icon tile + title + one metadata line, used at the top of result cards.
class _CardHeader extends StatelessWidget {
  final IconData icon;
  final _Tone tone;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _CardHeader({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TypeTile(icon: icon, tone: tone),
        const SizedBox(width: AppSpacing.md12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: type.sectionTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: type.metadata,
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

/// One fact of an inspected link: icon, [text] and an optional [figure] set
/// in DM Mono (or [fallback] in plain text when the figure is unknown).
class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? figure;
  final String? fallback;

  const _DetailLine({required this.icon, required this.text, this.figure, this.fallback});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final base = type.metadata.copyWith(color: palette.textPrimary);
    final figure = this.figure;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.sm8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: base,
                children: [
                  TextSpan(text: text),
                  if (figure != null)
                    TextSpan(
                      text: figure,
                      style: type.tabularFigures.copyWith(fontSize: 14, height: 20 / 14, color: palette.textPrimary),
                    )
                  else if (fallback != null)
                    TextSpan(text: fallback),
                ],
              ),
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

/// "SAVED  3" kicker above each group of rows (the overline role).
class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;

  const _GroupHeader({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final overline = AppTypography.of(palette).overline;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg16, bottom: AppSpacing.sm8),
      child: Semantics(
        header: true,
        label: '$title, $count',
        child: ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: title.toUpperCase(), style: overline),
                TextSpan(
                  text: '  $count',
                  style: overline.copyWith(
                    color: palette.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// The "Show all" toggle's place in the flattened download list.
class _SavedToggleRow {
  /// Saved downloads for the chosen kind chip, shown or not.
  final int total;
  final bool expanded;

  const _SavedToggleRow({required this.total, required this.expanded});

  /// Stable list key; prefixed so it never matches a task id or group key.
  static const Key key = ValueKey<String>('t_saved_toggle');
}

/// Ends the Saved group (DESIGN.md 7.14): "Show all 23 saved" opens the
/// older saved downloads in place, and the row, now "Show less", moves to the
/// end of the whole Saved list, right after the oldest one.
/// A text button with the expand glyph after its label; it tells a screen
/// reader whether the list is open.
class _SavedToggle extends StatelessWidget {
  final int total;
  final bool expanded;
  final VoidCallback onPressed;

  const _SavedToggle({
    super.key,
    required this.total,
    required this.expanded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final label = expanded ? 'Show less' : 'Show all $total saved';
    final spoken = expanded ? 'Show less saved downloads' : 'Show all $total saved downloads';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm8),
      child: Center(
        child: TextButton.icon(
          onPressed: onPressed,
          iconAlignment: IconAlignment.end,
          icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          // Inside the button, so the open / closed state lands on the
          // button's own node.
          label: Semantics(
            expanded: expanded,
            child: Text(label, semanticsLabel: spoken),
          ),
        ),
      ),
    );
  }
}

/// Icon-only row action; [emphasized] marks the main action of the row
/// with a tonal disc.
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
    final palette = context.palette;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      style: emphasized
          ? IconButton.styleFrom(
              backgroundColor: palette.primaryContainer,
              foregroundColor: palette.onPrimaryContainer,
            )
          : IconButton.styleFrom(foregroundColor: palette.textSecondary),
    );
  }
}

/// One download (DESIGN.md 7.14): cover or type tile, title, type and
/// quality tags, a 4 dp progress bar, the state as an icon and a word,
/// figures in DM Mono and the row actions. Watches only its own progress
/// entry so a running download does not rebuild the whole screen.
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
    final palette = context.palette;
    final type = AppTypography.of(palette);
    final update = ref.watch(downloadProgressMapProvider.select((m) => m[task.id]));
    final isActive = _isActiveState(task.state);
    final isCompleted = task.state == DownloadTaskState.completed.name;
    final isPaused = task.state == DownloadTaskState.paused.name;
    final isPausedOrQueued = isPaused || task.state == DownloadTaskState.queued.name;

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

    // "62%" in the figures role (textPrimary) while it runs or is paused...
    final String? percentText =
        knownTotal && (isActive || isPaused) ? '${(progressVal * 100).toStringAsFixed(0)}%' : null;

    // ...and speed, time left and size at 12 in textMuted, as chunks: a
    // number keeps its unit and a time its parts ("412.0 MB", "1m 45s" never
    // split), words keep ordinary spaces, and every later chunk starts with
    // its "· " or "/ ", so a narrow row wraps between chunks and no line ends
    // on a separator.
    String fig(String s) => s.replaceAll(' ', _nbsp);
    final List<String> sizeChunks;
    if (isCompleted) {
      sizeChunks = [fig(formatFileSize(task.receivedBytes > 0 ? task.receivedBytes : (total ?? 0)))];
    } else if (knownTotal) {
      sizeChunks = isActive || isPaused
          ? [fig(formatFileSize(received)), '/$_nbsp${fig(formatFileSize(total))}']
          : ['about ${fig(formatFileSize(total))}'];
    } else {
      sizeChunks = received > 0 ? [fig(formatFileSize(received)), '/${_nbsp}size unknown'] : ['Size unknown'];
    }
    final dotted = [
      if (isActive && speed != null && speed > 0) '${fig(formatFileSize(speed.round()))}/s',
      if (isActive && eta != null && eta.inSeconds > 0) '${fig(_formatEta(eta))} left',
      sizeChunks.first,
    ];
    final detailChunks = [
      for (final (i, part) in dotted.indexed) i == 0 ? part : '·$_nbsp$part',
      ...sizeChunks.skip(1),
    ];
    final detailSpoken = detailChunks.join(' ').replaceAll(_nbsp, ' ');

    // Progress bar (also while paused, so the user sees how far it got).
    final showProgress = isActive || (isPausedOrQueued && received > 0);
    final failedWithCode = task.state == DownloadTaskState.failed.name && task.errorCode != null;
    // Every state except "downloading" (where the % and speed say it) shows
    // its icon and word: Queued, Paused, Saved, Failed, Merging video and
    // audio...
    final showState = task.state != DownloadTaskState.downloading.name;
    final (stateIcon, stateTone) = _stateVisual(task.state);
    final stateColor = _toneColor(palette, stateTone);

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
                      style: type.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: AppSpacing.sm8,
                      runSpacing: AppSpacing.xs4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (kind != null)
                          PillTag(
                            text: kind == 'video' ? 'Video' : 'Audio',
                            icon: kind == 'video' ? Icons.videocam_rounded : Icons.music_note_rounded,
                            color: kind == 'video' ? palette.accent : palette.primary,
                          ),
                        if (quality != null && quality.isNotEmpty)
                          PillTag(text: quality, color: palette.textSecondary),
                        Text(
                          task.host,
                          style: type.metadata,
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
            // Sindur v2: a bold 8 dp bar in the slider colour (amber on ink,
            // wine on sand); a paused or waiting bar is muted, and its word
            // says why.
            LinearProgressIndicator(
              value: knownTotal ? progressVal : (isActive ? null : 0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: isActive ? palette.sliderActive : palette.textMuted,
              backgroundColor: palette.surfacePressed,
            ),
          ],
          const SizedBox(height: AppSpacing.sm8),
          LayoutBuilder(
            builder: (context, constraints) {
              final stateLine = <Widget>[
                if (showState)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(stateIcon, size: 16, color: stateColor),
                      const SizedBox(width: AppSpacing.xs4),
                      Flexible(
                        child: Text(
                          _formatStateText(task.state, task),
                          style: type.label.copyWith(fontSize: 13, height: 18 / 13, color: stateColor),
                        ),
                      ),
                    ],
                  ),
                if (percentText != null)
                  Text(percentText, style: type.tabularFigures.copyWith(color: palette.textPrimary)),
              ];
              final figures = Semantics(
                label: detailSpoken,
                child: ExcludeSemantics(
                  child: Wrap(
                    // About one space of DM Mono at 12.
                    spacing: 6,
                    children: [
                      for (final chunk in detailChunks)
                        Text(
                          chunk,
                          style: type.tabularFigures.copyWith(
                            fontSize: 12,
                            height: 16 / 12,
                            color: palette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              );
              // Beside the row actions the figures get what the buttons
              // leave. On a small phone or at large text that is too little
              // (each chunk on its own line), so the figures move under the
              // state and actions and take the card's full width.
              final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
              final besideActions = constraints.maxWidth - _kRowActionsWidth;
              final stacked = besideActions < _kMinFiguresWidth * textScale;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.md12,
                            runSpacing: AppSpacing.xs4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: stateLine,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm8),
                        actions,
                      ],
                    ),
                    figures,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.md12,
                      runSpacing: AppSpacing.xs4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [...stateLine, figures],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm8),
                  actions,
                ],
              );
            },
          ),
          if (failedWithCode) ...[
            const SizedBox(height: AppSpacing.xs4),
            Text(
              formatPlainErrorMessage(task.errorCode!, host: task.host),
              style: type.metadata,
            ),
            // The downloader's own reason ("[youtube] ...: Requested format is
            // not available") stays in the row and the diagnostics log: the
            // card says what happened in plain words only.
          ],
        ],
      ),
    );
  }
}

/// 48 dp cover at radius 14 (DESIGN.md 7.14): the download's own thumbnail,
/// the file's embedded art once saved, else the type tile (primary music
/// glyph, accent video glyph). A saved file shows a small play disc.
class _DownloadThumb extends StatelessWidget {
  final DownloadEntry task;
  final String? kind;

  static const double size = 48;

  const _DownloadThumb({required this.task, required this.kind});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isVideo = kind == 'video';
    final placeholderIcon = isVideo ? Icons.movie_outlined : Icons.music_note_rounded;
    final tile = _TypeTile(icon: placeholderIcon, tone: isVideo ? _Tone.accent : _Tone.brand);
    final thumb = task.thumbnailPath;
    final completed = task.state == DownloadTaskState.completed.name;

    Widget image;
    if (thumb != null) {
      image = Image.file(
        File(thumb),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 144,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => tile,
      );
    } else if (completed && task.finalPath != null) {
      // Direct downloads: embedded cover art / a video frame from the file itself.
      image = ArtworkThumbnail(
        uri: task.finalPath!,
        size: size,
        borderRadius: 0,
        placeholderIcon: placeholderIcon,
      );
    } else {
      return tile;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
            child: SizedBox(width: size, height: size, child: image),
          ),
          if (completed)
            Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: palette.overlay, shape: BoxShape.circle),
                child: Icon(Icons.play_arrow_rounded, size: 16, color: palette.onOverlay),
              ),
            ),
        ],
      ),
    );
  }
}

/// Static placeholder rows while the downloads list loads.
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.surfacePressed,
            borderRadius: BorderRadius.circular(AppSpacing.radiusBadge),
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
                      width: _DownloadThumb.size,
                      height: _DownloadThumb.size,
                      decoration: BoxDecoration(
                        color: palette.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
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
