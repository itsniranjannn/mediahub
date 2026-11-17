import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/motion_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/artwork_placeholder.dart';
import '../../shared/widgets/ui_kit.dart';
import '../downloads/download_providers.dart';
import '../downloads/downloads_notifier.dart';
import '../downloads/web_link_download_flow.dart';
import '../music_player/playback_notifier.dart';
import 'explore_notifier.dart';
import 'online_models.dart';
import 'online_source.dart';
import 'online_stream_sheet.dart';

/// Shown (like every other Listen/Watch failure) when a stream lookup returns
/// an address outside YouTube's media hosts.
const String _unexpectedPlayAddress = 'Unexpected stream address. Playback cancelled.';

/// Search YouTube, then play (audio or video) or download without leaving the app.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Id of the video whose stream is being looked up (shows a spinner on its card).
  String? _busyId;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    _focus.unfocus();
    ref.read(exploreProvider.notifier).search(value);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [job] while marking [video] busy; every failure becomes a friendly message.
  Future<void> _withBusy(OnlineVideo video, Future<void> Function() job) async {
    if (_busyId != null) return;
    setState(() => _busyId = video.id);
    try {
      await job();
    } on OnlineException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The stream address as a [Uri] when it is one of YouTube's own media
  /// hosts over https (`https://*.googlevideo.com/...`), otherwise null.
  /// Every stream URL is checked with this before it is played or downloaded,
  /// so a bad lookup result can never send the player or the downloader (and
  /// the phone's IP address) to some other server.
  static Uri? _trustedStreamUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host;
    return host == 'googlevideo.com' || host.endsWith('.googlevideo.com') ? uri : null;
  }

  /// [uri] is the address [_trustedStreamUri] accepted, as text: the players
  /// parse it again themselves, so they get exactly the normalized form that
  /// was checked rather than the raw lookup result.
  MediaItem _itemFor(OnlineVideo v, OnlineStream s, Uri uri, MediaType type) {
    return MediaItem(
      id: 'yt_${v.id}',
      uri: uri.toString(),
      mediaType: type,
      title: v.title,
      artist: v.author,
      durationMs: v.duration?.inMilliseconds ?? 0,
      sizeBytes: s.sizeBytes,
      format: s.container,
      dateAdded: DateTime.now(),
      source: 'online',
      artworkPath: v.thumbnailUrl.isEmpty ? null : v.thumbnailUrl,
    );
  }

  Future<void> _playAudio(OnlineVideo v) {
    return _withBusy(v, () async {
      final streams = await ref.read(onlineSourceProvider).streams(v.id);
      final s = streams.bestAudio;
      if (s == null) throw const OnlineException('No audio stream found for this video.');
      final uri = _trustedStreamUri(s.url);
      if (uri == null) throw const OnlineException(_unexpectedPlayAddress);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      await ref.read(playbackNotifierProvider.notifier).loadQueue([_itemFor(v, s, uri, MediaType.audio)]);
    });
  }

  Future<void> _watch(OnlineVideo v) {
    return _withBusy(v, () async {
      final streams = await ref.read(onlineSourceProvider).streams(v.id);
      final s = streams.bestVideo;
      if (s == null) throw const OnlineException('No video stream found for this video.');
      final uri = _trustedStreamUri(s.url);
      if (uri == null) throw const OnlineException(_unexpectedPlayAddress);
      if (!mounted) return;
      context.push('/video_player', extra: _itemFor(v, s, uri, MediaType.video));
    });
  }

  Future<void> _download(OnlineVideo v) async {
    if (v.isLive) {
      _snack('Live streams cannot be downloaded.');
      return;
    }
    // Android with the yt-dlp downloader: every quality up to 4K, merged to one file.
    if (WebLinkDownloadFlow.isAvailable(ref)) {
      await WebLinkDownloadFlow.start(context, ref, Uri.parse(v.watchUrl));
      return;
    }
    // iOS (or downloader switched off): the ready-made streams, via the direct-link engine.
    await _withBusy(v, () async {
      final streams = await ref.read(onlineSourceProvider).streams(v.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => OnlineStreamSheet(
          video: v,
          streams: streams,
          onSelect: (s) => _enqueueStream(v, s),
        ),
      );
    });
  }

  Future<void> _enqueueStream(OnlineVideo v, OnlineStream s) async {
    // Only YouTube's own media hosts are ever downloaded from here.
    final uri = _trustedStreamUri(s.url);
    if (uri == null) {
      _snack('Unexpected download address. Download cancelled.');
      return;
    }
    // Called fire-and-forget from the quality sheet, so every failure must be
    // handled here: an escaped error would vanish without telling the user.
    try {
      if (!await WebLinkDownloadFlow.confirmNotice(context, ref)) return;
      await WebLinkDownloadFlow.ensureNotificationPermission();
      if (!mounted) return;

      // Both are app-wide; capture them so the queue still starts if this
      // screen goes away while the download row is being written.
      final engine = ref.read(downloadEngineProvider);
      final coordinator = ref.read(downloadQueueCoordinatorProvider.notifier);
      final ext = s.isAudio && s.container == 'mp4' ? 'm4a' : s.container;
      await engine.enqueueDownload(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: uri,
        displayName: v.title,
        suggestedFileName: '${v.title}.$ext',
        kind: s.isAudio ? 'audio' : 'video',
        thumbnailUrl: v.thumbnailUrl,
        qualityLabel: s.label,
        uploader: v.author,
        durationSec: v.duration?.inSeconds,
        totalBytes: s.sizeBytes > 0 ? s.sizeBytes : null,
      );
      coordinator.trigger();
      if (mounted) _snack('Added to Downloads: ${v.title} (${s.label})');
    } catch (_) {
      if (mounted) _snack('Could not add the download. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exploreProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _searchField(state)),
            if (!state.hasSearched && state.history.isNotEmpty)
              SliverToBoxAdapter(child: _history(state)),
            if (state.loading)
              SliverList.builder(
                itemCount: 3,
                itemBuilder: (_, _) => const _SkeletonCard(),
              )
            else if (state.error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.wifi_off_rounded,
                  title: 'Could not search',
                  message: state.error!,
                  action: FilledButton.tonal(
                    onPressed: () => ref.read(exploreProvider.notifier).search(state.query),
                    child: const Text('Try again'),
                  ),
                ),
              )
            else if (state.hasSearched && state.results.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.search_off_rounded,
                  title: 'No results',
                  message: 'Try different words or a shorter search.',
                ),
              )
            else if (!state.hasSearched)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyHint(
                  icon: Icons.travel_explore_rounded,
                  title: 'Find anything to watch or listen to',
                  message: 'Search YouTube, then play it right here or save it for offline.',
                ),
              )
            else
              SliverList.builder(
                itemCount: state.results.length,
                itemBuilder: (context, i) {
                  final v = state.results[i];
                  return _ResultCard(
                    video: v,
                    busy: _busyId == v.id,
                    onPlayAudio: () => _playAudio(v),
                    onWatch: () => _watch(v),
                    onDownload: () => _download(v),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl32)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.xl20, AppSpacing.lg16, AppSpacing.md12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Explore', style: AppTypography.display)),
          const SizedBox(height: 4),
          Text('Search, play and save without leaving MediaHub.', style: AppTypography.metadata),
        ],
      ),
    );
  }

  Widget _searchField(ExploreState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, AppSpacing.sm8),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        onChanged: (_) => setState(() {}),
        style: AppTypography.body,
        decoration: InputDecoration(
          hintText: 'Search videos, songs, channels',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                  },
                ),
        ),
      ),
    );
  }

  Widget _history(ExploreState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: AppTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => ref.read(exploreProvider.notifier).clearHistory(),
                child: const Text('Clear'),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.sm8,
            runSpacing: AppSpacing.sm8,
            children: [
              for (final q in state.history)
                InputChip(
                  label: Text(q),
                  avatar: const Icon(Icons.history_rounded, size: 16),
                  onPressed: () {
                    _controller.text = q;
                    _submit(q);
                  },
                  onDeleted: () => ref.read(exploreProvider.notifier).removeFromHistory(q),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final OnlineVideo video;
  final bool busy;
  final VoidCallback onPlayAudio;
  final VoidCallback onWatch;
  final VoidCallback onDownload;

  const _ResultCard({
    required this.video,
    required this.busy,
    required this.onPlayAudio,
    required this.onWatch,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final duration = video.duration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Thumbnail(url: video.thumbnailUrl, seed: video.id),
                    // No scrim: the badge has its own dark chip, so bright
                    // frames keep their colours. Same corner as the video
                    // cards' badge.
                    Positioned(
                      right: AppSpacing.md12,
                      bottom: AppSpacing.md12,
                      child: video.isLive
                          ? const DurationBadge.live()
                          : (duration != null && duration > Duration.zero)
                              ? DurationBadge(duration: duration)
                              : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.md12, AppSpacing.lg16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    breakableTitle(video.title),
                    semanticsLabel: video.title,
                    style: AppTypography.bodyStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(video.author, style: AppTypography.metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Padding(
              // On the same 16 dp gutter as the title and the author.
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, AppSpacing.sm8, AppSpacing.lg16, AppSpacing.lg16),
              child: busy
                  ? const SizedBox(
                      // As tall as the buttons it stands in for.
                      height: AppSpacing.minTouchTarget,
                      child: Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: onPlayAudio,
                            icon: const Icon(Icons.headphones_rounded, size: 20),
                            label: const Text('Listen'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onWatch,
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: const Text('Watch'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm8),
                        IconButton.outlined(
                          // As tall as the Listen / Watch pills beside it.
                          style: IconButton.styleFrom(fixedSize: const Size.square(AppSpacing.minTouchTarget)),
                          tooltip: 'Download',
                          onPressed: video.isLive ? null : onDownload,
                          icon: const Icon(Icons.download_rounded),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Online still, faded in over a placeholder in the result's own colours.
class _Thumbnail extends StatelessWidget {
  final String url;

  /// Seeds the placeholder colours (the video id).
  final String seed;

  const _Thumbnail({required this.url, required this.seed});

  @override
  Widget build(BuildContext context) {
    final placeholder = ArtworkPlaceholder(
      seed: seed,
      icon: Icons.play_circle_outline_rounded,
    );
    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 720,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            placeholder,
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: MotionTokens.duration(context, MotionTokens.page),
              curve: MotionTokens.easeOut,
              child: child,
            ),
          ],
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.sm8),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(220, 14), const SizedBox(height: 8), bar(120, 12), const SizedBox(height: 16), bar(double.infinity, 40)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
