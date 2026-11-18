import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/ui_kit.dart';
import 'playback_notifier.dart';

const double _kRowRadius = AppSpacing.radiusThumb;
const EdgeInsets _kRowInset = EdgeInsets.symmetric(horizontal: AppSpacing.sm8, vertical: 2);

/// Rows grow with the text instead of clipping it (docs/DESIGN.md 6).
const double _kRowMinHeight = 64;

/// The track-number column ("01"), where the current row shows the
/// equaliser instead.
const double _kIndexWidth = 32;

/// The current row's leading bar (docs/DESIGN.md 7.6): 3 dp, 12 dp in from
/// the row's top and bottom.
const double _kNowBarWidth = 3;
const double _kNowBarInset = AppSpacing.md12;

/// The play queue, shown in the app's standard bottom sheet (surface colour,
/// rounded top and drag handle come from the app theme, light or dark). Tap a
/// row to jump to it, drag the grip to reorder, swipe left or tap the minus
/// to remove.
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
                      // Under TalkBack / VoiceOver the swipe would turn into
                      // unlabelled scroll actions on the row, and "scroll
                      // forward" would remove the track. The row's "Remove
                      // from queue" button does it instead.
                      direction: MediaQuery.accessibleNavigationOf(context)
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
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
  /// row's own shape instead of running edge to edge.
  static Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final palette = context.palette;
        final t = Curves.easeOut.transform(animation.value);
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: _kRowInset,
                  child: Material(
                    color: palette.surfaceElevated,
                    elevation: 8 * t,
                    shadowColor: Theme.of(context).colorScheme.shadow,
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
    final type = context.typography;
    final tracks = count == 1 ? '1 track' : '$count tracks';
    final subtitle = count > 1 ? '$tracks · Drag to reorder' : tracks;

    return Padding(
      // "Close" ends on the 16 dp gutter, like SectionHeader's action.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        0,
        AppSpacing.lg16 - SectionHeader.actionButtonPadding,
        AppSpacing.md12,
      ),
      child: Row(
        children: [
          Expanded(
            // One heading stop, "Current queue / 1 track", like Now Playing's
            // header: on its own the shorter subtitle was read first.
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Current queue',
                      style: type.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: type.metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm8),
          TextButton(
            style: SectionHeader.actionStyle,
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

/// Revealed while a row is swiped to the left: the error colour with an
/// icon and a word, never colour alone.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: _kRowInset,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.errorContainer,
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
                  style: context.typography.button.copyWith(color: palette.onErrorContainer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm8),
              Icon(Icons.delete_rounded, color: palette.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// The track number ("01") in the `index` type, or, on the current row, the
/// equaliser glyph in primary in its place (docs/DESIGN.md 7.6).
class _QueueIndex extends StatelessWidget {
  final int index;
  final bool isCurrent;

  const _QueueIndex({required this.index, required this.isCurrent});

  /// "01" ... "99", then "100".
  static String label(int index) => (index + 1).toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: _kIndexWidth,
      child: isCurrent
          ? Icon(
              Icons.graphic_eq_rounded,
              color: palette.primary,
              size: 20,
              semanticLabel: 'Now playing',
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label(index),
                maxLines: 1,
                style: context.typography.index,
                textAlign: TextAlign.center,
              ),
            ),
    );
  }
}

/// One queue entry (docs/DESIGN.md 7.10): the track number (the equaliser on
/// the current track, which also wears the 3 dp primary bar and a primary
/// title), title / artist, the remove button and a 24 dp reorder grip.
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
    final palette = context.palette;
    final type = context.typography;
    final artist = item.artist ?? 'Unknown Artist';
    final radius = BorderRadius.circular(_kRowRadius);
    return Padding(
      padding: _kRowInset,
      // One node per row, worded like a song row in the library: this label
      // and tap stand in for the ink well and the texts, which are left out
      // below, and the current track is the selected one (its "Now playing"
      // glyph is not read on top of that). Not a container, so the list's
      // "Move up / down" actions stay on this node (the swipe is off while a
      // screen reader runs). The remove button is its own; the grip is
      // covered by those moves.
      child: Semantics(
        label: 'Song: ${item.title} by $artist',
        button: true,
        selected: isCurrent,
        onTap: onTap,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            highlightColor: palette.surfacePressed,
            child: Stack(
              children: [
                if (isCurrent)
                  PositionedDirectional(
                    start: 0,
                    top: _kNowBarInset,
                    bottom: _kNowBarInset,
                    width: _kNowBarWidth,
                    child: DecoratedBox(
                      key: const ValueKey('queue_now_bar'),
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _kRowMinHeight),
                  child: Padding(
                    // 8 dp row inset + 8 dp here = the 16 dp gutter of the header
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.sm8, AppSpacing.sm8, 0, AppSpacing.sm8),
                    child: Row(
                      children: [
                        ExcludeSemantics(child: _QueueIndex(index: index, isCurrent: isCurrent)),
                        const SizedBox(width: AppSpacing.md12),
                        Expanded(
                          child: ExcludeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.bodyStrong.copyWith(
                                    color: isCurrent ? palette.primary : palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.metadata,
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                          color: palette.textSecondary,
                          tooltip: 'Remove from queue',
                          onPressed: onRemove,
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: SizedBox.square(
                            dimension: AppSpacing.minTouchTarget,
                            child: Icon(
                              Icons.drag_handle_rounded,
                              size: 24,
                              color: palette.dragHandle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
