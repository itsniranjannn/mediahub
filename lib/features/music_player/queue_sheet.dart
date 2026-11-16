import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/artwork_thumbnail.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/ui_kit.dart';
import 'playback_notifier.dart';

const double _kRowRadius = AppSpacing.buttonRadius;
const EdgeInsets _kRowInset = EdgeInsets.symmetric(horizontal: AppSpacing.sm8, vertical: 2);
const double _kThumbSize = 44;

/// The play queue, shown in the app's standard bottom sheet (surface colour,
/// rounded top and drag handle come from the theme). Tap a row to jump to it,
/// drag the handle to reorder, swipe left or tap the minus to remove.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackNotifierProvider);
    final notifier = ref.read(playbackNotifierProvider.notifier);
    final queue = playbackState.queue;
    final currentIndex = playbackState.queueIndex;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        _QueueHeader(
          count: queue.length,
          onClose: () => Navigator.of(context).pop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: queue.isEmpty
              ? const _EmptyQueue()
              : ReorderableListView.builder(
                  padding: EdgeInsets.only(
                    top: AppSpacing.sm8,
                    bottom: bottomInset + AppSpacing.lg16,
                  ),
                  itemCount: queue.length,
                  proxyDecorator: _liftedRow,
                  onReorderItem: (oldIndex, newIndex) {
                    notifier.reorderQueue(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final isCurrent = index == currentIndex;

                    return Dismissible(
                      key: ValueKey('${item.id}_$index'),
                      direction: DismissDirection.endToStart,
                      background: const _RemoveBackground(),
                      onDismissed: (_) {
                        notifier.removeQueueItemAt(index);
                      },
                      child: _QueueRow(
                        item: item,
                        index: index,
                        isCurrent: isCurrent,
                        onTap: () {
                          notifier.skipToQueueItem(index);
                        },
                        onRemove: () {
                          notifier.removeQueueItemAt(index);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The row being dragged lifts onto an elevated rounded surface. The surface
  /// uses the same inset and corners as a resting row, so it lines up with the
  /// row's own tint instead of running edge to edge.
  static Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: _kRowInset,
                  child: Material(
                    color: AppColors.surfaceElevated,
                    elevation: 8 * t,
                    shadowColor: Colors.black,
                    borderRadius: BorderRadius.circular(_kRowRadius),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: child,
    );
  }
}

class _QueueHeader extends StatelessWidget {
  final int count;
  final VoidCallback onClose;

  const _QueueHeader({required this.count, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final tracks = count == 1 ? '1 track' : '$count tracks';
    final subtitle = count > 1 ? '$tracks · Drag to reorder' : tracks;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        0,
        AppSpacing.sm8,
        AppSpacing.md12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Current Queue',
                    style: AppTypography.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm8),
          TextButton(
            onPressed: onClose,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    // Scrolls rather than overflowing when the sheet is short (landscape).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const EmptyHint(
            icon: Icons.queue_music_rounded,
            title: 'Queue is empty',
            message: 'Play a song, or choose "Add to queue" from its menu.',
          ),
        ),
      ),
    );
  }
}

/// Revealed while a row is swiped to the left.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _kRowInset,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(_kRowRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  'Remove',
                  style: AppTypography.button.copyWith(color: AppColors.error),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm8),
              const Icon(Icons.delete_rounded, color: AppColors.error),
            ],
          ),
        ),
      ),
    );
  }
}

/// One queue entry: position (or an equaliser glyph for the current track),
/// cover, title / artist, remove button and drag handle.
class _QueueRow extends StatelessWidget {
  final MediaItem item;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueRow({
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _kRowInset,
      child: Semantics(
        selected: isCurrent,
        child: Material(
          color: isCurrent ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(_kRowRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              // 8 dp row inset + 8 dp here = the 16 dp gutter of the header
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm8, AppSpacing.sm8, 0, AppSpacing.sm8),
              child: Row(
                children: [
                  SizedBox(
                    width: AppSpacing.xxxl32,
                    child: Center(
                      child: isCurrent
                          ? const Icon(
                              Icons.graphic_eq_rounded,
                              color: AppColors.primary,
                              size: 20,
                              semanticLabel: 'Now playing',
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${index + 1}',
                                style: AppTypography.tabularFigures.copyWith(color: AppColors.textMuted),
                                maxLines: 1,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm8),
                  ArtworkThumbnail(
                    uri: item.uri,
                    artworkPath: item.artworkPath,
                    size: _kThumbSize,
                    // same corners as the mini player's cover
                    borderRadius: AppSpacing.md12,
                  ),
                  const SizedBox(width: AppSpacing.md12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyStrong.copyWith(
                            color: isCurrent ? AppColors.primary : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.metadata,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                    color: AppColors.textMuted,
                    tooltip: 'Remove from queue',
                    onPressed: onRemove,
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const SizedBox.square(
                      dimension: AppSpacing.minTouchTarget,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
