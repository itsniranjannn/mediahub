import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_colors.dart';
import '../../data/repositories/library_repository_impl.dart';

class FavoriteFeedbackButton extends ConsumerStatefulWidget {
  final String itemId;
  final bool isFavorite;
  final double size;
  final EdgeInsetsGeometry padding;
  final BoxConstraints constraints;

  const FavoriteFeedbackButton({
    super.key,
    required this.itemId,
    required this.isFavorite,
    this.size = 24.0,
    this.padding = const EdgeInsets.all(8.0),
    this.constraints = const BoxConstraints(minWidth: 48, minHeight: 48),
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
    final nextFavorite = !widget.isFavorite;

    // 3. Toggle favorite state in repository
    await repo.toggleFavorite(widget.itemId);

    if (!mounted) return;

    // 4. Floating snackbar with Undo above mini-player
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          nextFavorite ? 'Added to Favorites' : 'Removed from Favorites',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 76),
        duration: const Duration(seconds: 3),
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
    final label = widget.isFavorite ? 'Remove from favorites' : 'Add to favorites';

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
            widget.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey<bool>(widget.isFavorite),
            color: widget.isFavorite ? AppColors.error : AppColors.textSecondary,
            size: widget.size,
          ),
        ),
        onPressed: _handleToggle,
      ),
    );
  }
}
