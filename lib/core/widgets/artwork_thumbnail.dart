// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../app/theme/app_palette.dart';
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
    this.borderRadius = AppSpacing.radiusThumb,
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
          color: context.palette.surface,
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
    return _FadeInOver(placeholder: placeholder, loaded: frame != null, child: child);
  };
}

/// [child] fading in over [placeholder]. Once the cover is fully opaque the
/// placeholder leaves the tree, so long lists do not paint two layers per
/// cover; with reduced motion it goes as soon as the first frame is there.
/// It comes back while a new image loads (the image source changed).
class _FadeInOver extends StatefulWidget {
  final Widget placeholder;

  /// Whether the image has its first frame.
  final bool loaded;
  final Widget child;

  const _FadeInOver({required this.placeholder, required this.loaded, required this.child});

  @override
  State<_FadeInOver> createState() => _FadeInOverState();
}

class _FadeInOverState extends State<_FadeInOver> {
  /// The cover is fully opaque; only it is painted.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    // Built with a frame already there: the cover starts opaque, no fade.
    _covered = widget.loaded;
  }

  @override
  void didUpdateWidget(covariant _FadeInOver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.loaded) _covered = false;
  }

  /// Called by the ticker when a fade ends (never during a build).
  void _onFadeEnd() {
    if (mounted && widget.loaded && !_covered) setState(() => _covered = true);
  }

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.duration(context, MotionTokens.page);
    final animates = duration > Duration.zero;
    final loaded = widget.loaded;
    final showPlaceholder = !loaded || (animates && !_covered);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showPlaceholder) widget.placeholder,
        // Last child, so it keeps its element when the placeholder goes.
        AnimatedOpacity(
          opacity: loaded ? 1 : 0,
          duration: duration,
          curve: MotionTokens.easeOut,
          // A zero-length fade ends inside the build; nothing to wait for.
          onEnd: animates ? _onFadeEnd : null,
          child: widget.child,
        ),
      ],
    );
  }
}

/// The art the device has for [uri] (embedded cover, MediaStore thumbnail or
/// video frame), looked up once per uri and size and kept across rebuilds.
///
/// While a list is flung fast ([Scrollable.recommendDeferredLoadingForContext])
/// the platform lookup waits a frame at a time, so rows that only fly past
/// never ask the phone for their cover. A web link (an Online item without a
/// thumbnail) has no device art and is never looked up.
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
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first lookup waits for the scroll context (not reachable in
    // initState).
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant _ServiceArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.lookupSize != widget.lookupSize) {
      _load();
    }
  }

  static bool _isWebLink(String uri) => uri.startsWith('https://') || uri.startsWith('http://');

  void _load() {
    final uri = widget.uri;
    final size = widget.lookupSize;
    final key = '$uri@$size';
    _key = key;

    // Already loaded once: paint it on this frame.
    final cached = ArtworkService.instance.peek(uri, size: size);
    _bytes = cached;
    if (cached != null || uri.isEmpty || _isWebLink(uri)) return;
    _lookUp(uri, size, key);
  }

  void _lookUp(String uri, int size, String key) {
    if (!mounted || _key != key) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      // Flung past at speed: try again next frame.
      SchedulerBinding.instance.scheduleFrameCallback((_) => _lookUp(uri, size, key));
      return;
    }
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
