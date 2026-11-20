import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_palette.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../features/music_player/playback_notifier.dart' show appDatabaseProvider;

/// Live favorite flag straight from the database. The playback queue holds a
/// snapshot of each song taken when it was queued, so reading `isFavorite` from
/// the playing item left the heart stuck on its old state.
final isFavoriteProvider = StreamProvider.autoDispose.family<bool, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.mediaItemsTable)..where((t) => t.id.equals(id)))
      .watchSingleOrNull()
      .map((row) => row?.isFavorite ?? false);
});

class FavoriteFeedbackButton extends ConsumerStatefulWidget {
  final String itemId;
  final bool isFavorite;
  final double size;
  final EdgeInsetsGeometry padding;
  final BoxConstraints constraints;

  /// Distance of the confirmation snackbar from the bottom edge (raise it on
  /// screens whose bottom area holds controls, e.g. Now Playing).
  final double snackBottomMargin;

  const FavoriteFeedbackButton({
    super.key,
    required this.itemId,
    required this.isFavorite,
    this.size = 24.0,
    this.padding = const EdgeInsets.all(8.0),
    this.constraints = const BoxConstraints(minWidth: 48, minHeight: 48),
    this.snackBottomMargin = 76,
  });

  @override
  ConsumerState<FavoriteFeedbackButton> createState() => _FavoriteFeedbackButtonState();
}

class _FavoriteFeedbackButtonState extends ConsumerState<FavoriteFeedbackButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 50),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isFavorite =>
      ref.read(isFavoriteProvider(widget.itemId)).asData?.value ?? widget.isFavorite;

  Future<void> _handleToggle() async {
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion = mediaQuery.disableAnimations;

    // 1. Light haptic feedback
    HapticFeedback.lightImpact();

    // 2. 160ms scale animation (respect reduced motion)
    if (!reduceMotion) {
      _controller.forward(from: 0.0);
    }

    final repo = ref.read(libraryRepositoryProvider);
    final nextFavorite = !_isFavorite;

    // 3. Toggle favorite state in repository
    await repo.toggleFavorite(widget.itemId);

    if (!mounted) return;

    // 4. Floating snackbar with Undo above mini-player
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          nextFavorite ? 'Added to Favourites' : 'Removed from Favourites',
        ),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: widget.snackBottomMargin),
        duration: const Duration(seconds: 3),
        // Since Flutter 3.29 a snackbar with an action never times out unless told to.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            repo.toggleFavorite(widget.itemId);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite =
        ref.watch(isFavoriteProvider(widget.itemId)).asData?.value ?? widget.isFavorite;
    final label = isFavorite ? 'Remove from Favourites' : 'Add to Favourites';

    return Semantics(
      label: label,
      button: true,
      child: IconButton(
        iconSize: widget.size,
        padding: widget.padding,
        constraints: widget.constraints,
        tooltip: label,
        icon: ScaleTransition(
          scale: _scaleAnimation,
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey<bool>(isFavorite),
            // Favourite pink, not the error colour (coral since the redesign).
            color: isFavorite ? context.palette.favorite : context.palette.textSecondary,
            size: widget.size,
          ),
        ),
        onPressed: _handleToggle,
      ),
    );
  }
}
