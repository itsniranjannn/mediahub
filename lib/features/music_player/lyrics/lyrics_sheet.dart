// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/motion_tokens.dart';
import '../../../domain/models/media_item.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../playback_notifier.dart';
import 'lyrics.dart';
import 'lyrics_repository.dart';

/// Opens the lyrics of the song playing now (from the Now Playing footer).
Future<void> showLyricsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.8, child: LyricsSheet()),
  );
}

/// The current song's lyrics. Synced lyrics follow the music: the line
/// being sung is in the primary colour and kept in the middle; tapping a
/// line jumps there. Plain lyrics simply scroll.
class LyricsSheet extends ConsumerWidget {
  const LyricsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playbackNotifierProvider.select((s) => s.currentItem));
    final type = context.typography;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.sm8, AppSpacing.md12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusArtSmall),
                ),
                child: Icon(Icons.lyrics_rounded, size: 20, color: palette.primary),
              ),
              const SizedBox(width: AppSpacing.md12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text('Lyrics', style: type.sectionTitle)),
                    if (item != null)
                      Text(
                        [item.title, if (item.artist != null) item.artist!].join(' · '),
                        style: type.metadata.copyWith(color: palette.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.divider),
        Expanded(child: item == null ? const _NoLyrics(online: false) : _LyricsBody(item: item)),
      ],
    );
  }
}

class _LyricsBody extends ConsumerWidget {
  const _LyricsBody({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsForProvider(item));
    final online = ref.watch(onlineLyricsProvider);
    return lyrics.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _NoLyrics(online: online),
      data: (l) => l == null ? _NoLyrics(online: online) : SyncedLyricsView(lyrics: l),
    );
  }
}

class _NoLyrics extends StatelessWidget {
  const _NoLyrics({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return EmptyHint(
      icon: Icons.lyrics_rounded,
      title: 'No lyrics for this song',
      message: online
          ? 'Not in the file, not in a .lrc file next to it, and LRCLIB has none.'
          : 'Not in the file or in a .lrc file next to it. You can turn on "Find lyrics online" in Settings.',
    );
  }
}

/// The lines of [lyrics], following the player's position when synced.
class SyncedLyricsView extends ConsumerStatefulWidget {
  const SyncedLyricsView({super.key, required this.lyrics});

  final Lyrics lyrics;

  /// Height of one line slot (two lines of text fit; longer lines grow).
  static const double lineExtent = 56;

  @override
  ConsumerState<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<SyncedLyricsView> {
  final ScrollController _scroll = ScrollController();
  int _shown = -1;

  /// The user scrolled by hand: stop following for a few seconds.
  DateTime? _userScrolledAt;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int index) {
    if (index == _shown) return;
    _shown = index;
    final since = _userScrolledAt;
    if (since != null && DateTime.now().difference(since) < const Duration(seconds: 4)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || index < 0) return;
      final viewport = _scroll.position.viewportDimension;
      final target = (index * SyncedLyricsView.lineExtent - viewport / 2 + SyncedLyricsView.lineExtent / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: MotionTokens.duration(context, MotionTokens.feedback),
        curve: MotionTokens.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final palette = context.palette;
    final type = context.typography;
    final synced = lyrics.isSynced;
    final position = synced ? (ref.watch(throttledPositionStreamProvider).value ?? Duration.zero) : Duration.zero;
    final current = lyrics.lineAt(position);
    if (synced) _follow(current);
    final source = switch (lyrics.source) {
      LyricsSource.sidecar => 'From a .lrc file',
      LyricsSource.embedded => 'From the song file',
      LyricsSource.online => 'From LRCLIB',
    };
    // Landscape and tablets: lines stay in a readable 640 dp column.
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width > 688 ? (width - 640) / 2 : AppSpacing.xxl24;
    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('lyrics_list'),
        controller: _scroll,
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: AppSpacing.lg16),
        itemCount: lyrics.lines.length + 1,
        itemExtent: synced ? SyncedLyricsView.lineExtent : null,
        itemBuilder: (context, i) {
          if (i == lyrics.lines.length) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: palette.divider),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusBadge),
                ),
                child: Text(source, style: type.metadata.copyWith(color: palette.textMuted)),
              ),
            );
          }
          final line = lyrics.lines[i];
          final active = i == current;
          final text = Text(
            line.text.isEmpty ? '♪' : line.text,
            maxLines: synced ? 2 : null,
            overflow: synced ? TextOverflow.ellipsis : null,
            style: type.body.copyWith(
              fontSize: active ? 20 : 18,
              height: 1.3,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: !synced
                  ? palette.textPrimary
                  : active
                      ? palette.primary
                      : (i < current ? palette.textMuted : palette.textSecondary),
            ),
          );
          if (!synced) {
            return Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs4), child: text);
          }
          return InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusThumb),
            onTap: () {
              _userScrolledAt = null;
              ref.read(playbackNotifierProvider.notifier).seek(line.time!);
            },
            child: Align(alignment: Alignment.centerLeft, child: text),
          );
        },
      ),
    );
  }
}
