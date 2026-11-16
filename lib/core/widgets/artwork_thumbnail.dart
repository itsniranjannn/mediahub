import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/motion_tokens.dart';
import '../../shared/widgets/artwork_placeholder.dart';
import '../services/artwork_service.dart';

/// Cover art for a song or video, cropped once into its box.
///
/// Sources, in order: [artworkPath] (an http(s) URL for online items, or a
/// local image such as the one saved with a download), then the art the
/// device has for [uri]. While loading, on error and when there is none, an
/// [ArtworkPlaceholder] seeded with [uri] shows instead, and real artwork
/// fades in over it.
///
/// Square by default ([size]); pass [width] and [height] for other shapes,
/// e.g. a 16:9 video still. Inside a parent with tight constraints (an
/// [AspectRatio], a [Stack] with [StackFit.expand]) the box takes the
/// parent's size and [width] / [height] only pick the decode resolution.
class ArtworkThumbnail extends StatelessWidget {
  final String uri;

  /// Local image file (e.g. the thumbnail saved with a downloaded video).
  /// Preferred over the native lookup when present.
  final String? artworkPath;
  final double size;
  final double borderRadius;
  final IconData placeholderIcon;

  /// Box width; defaults to [size].
  final double? width;

  /// Box height; defaults to [size].
  final double? height;

  /// Seeds the placeholder colours; defaults to [uri]. Albums and artists
  /// pass their own name so their cover matches their tile.
  final String? placeholderSeed;

  const ArtworkThumbnail({
    super.key,
    required this.uri,
    this.artworkPath,
    this.size = 48,
    this.borderRadius = AppSpacing.buttonRadius,
    this.placeholderIcon = Icons.music_note_rounded,
    this.width,
    this.height,
    this.placeholderSeed,
  });

  /// Decode width multiplier (covers the densest phone screens).
  static const double _decodeScale = 3;
  static const int _maxDecodeWidth = 1440;

  /// Platform lookup size. Few buckets, so lists, the mini player and Now
  /// Playing share the service cache.
  static int _lookupSize(double longestSide) {
    if (longestSide <= 150) return 256;
    if (longestSide <= 300) return 512;
    return 1024;
  }

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final placeholder = ArtworkPlaceholder(
      seed: placeholderSeed ?? uri,
      icon: placeholderIcon,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: w,
        height: h,
        child: ColoredBox(
          color: AppColors.surface,
          child: _image(w, h, placeholder),
        ),
      ),
    );
  }

  Widget _image(double w, double h, Widget placeholder) {
    final finiteWidth = w.isFinite ? w : (h.isFinite ? h : size);
    final cacheWidth = math.min((finiteWidth * _decodeScale).round(), _maxDecodeWidth);
    final longest = math.max(finiteWidth, h.isFinite ? h : finiteWidth);
    final fromService = _ServiceArtwork(
      uri: uri,
      lookupSize: _lookupSize(longest),
      placeholder: placeholder,
    );

    final path = artworkPath;
    if (path == null || path.isEmpty) return fromService;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      // Thumbnail of an online (streamed) item.
      return Image.network(
        path,
        fit: BoxFit.cover,
        width: w,
        height: h,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        frameBuilder: _fadeInOver(placeholder),
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: w,
      height: h,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      frameBuilder: _fadeInOver(placeholder),
      // A saved image that has gone missing falls back to the device's art.
      errorBuilder: (_, _, _) => fromService,
    );
  }
}

/// Fades a cover in over [placeholder] the first time it decodes. A cover
/// already in the image cache paints straight away; with reduced motion the
/// swap is instant.
ImageFrameBuilder _fadeInOver(Widget placeholder) {
  return (context, child, frame, wasSynchronouslyLoaded) {
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
  };
}

/// The art the device has for [uri] (embedded cover, MediaStore thumbnail or
/// video frame), looked up once per uri and size and kept across rebuilds.
class _ServiceArtwork extends StatefulWidget {
  final String uri;
  final int lookupSize;
  final Widget placeholder;

  const _ServiceArtwork({
    required this.uri,
    required this.lookupSize,
    required this.placeholder,
  });

  @override
  State<_ServiceArtwork> createState() => _ServiceArtworkState();
}

class _ServiceArtworkState extends State<_ServiceArtwork> {
  String _key = '';
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ServiceArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.lookupSize != widget.lookupSize) {
      _load();
    }
  }

  void _load() {
    final uri = widget.uri;
    final size = widget.lookupSize;
    final key = '$uri@$size';
    _key = key;

    // Already loaded once: paint it on this frame.
    final cached = ArtworkService.instance.peek(uri, size: size);
    _bytes = cached;
    if (cached != null) return;

    ArtworkService.instance
        .getArtwork(uri, size: size)
        .catchError((Object _) => null)
        .then((bytes) {
      if (!mounted || _key != key || identical(bytes, _bytes)) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.placeholder;
    // The thumbnail's box is tight, so the image fills it.
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: _fadeInOver(widget.placeholder),
      errorBuilder: (_, _, _) => widget.placeholder,
    );
  }
}
