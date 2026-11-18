import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../domain/repositories/video_engine.dart';

class OfficialVideoEngine implements VideoEngine, VideoEngineExtras {
  VideoPlayerController? _controller;
  final _positionController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _completedController = StreamController<void>.broadcast();
  final _captionController = StreamController<String>.broadcast();
  Timer? _positionTimer;
  bool _isDisposed = false;
  bool _wasCompleted = false;
  bool? _lastPlaying;
  String _lastCaption = '';

  OfficialVideoEngine({VideoPlayerController? controller}) {
    _controller = controller;
  }

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Size get videoSize => _controller?.value.size ?? Size.zero;

  @override
  double get aspectRatio => _controller?.value.aspectRatio ?? (16 / 9);

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  @override
  Stream<String?> get errorStream => _errorController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Stream<String> get captionStream => _captionController.stream;

  @override
  int? get platformPlayerId {
    final c = _controller;
    if (c == null) return null;
    // The plugin marks the id "for testing", but it is the only handle on the
    // native player; the patched video_player_android maps it to the
    // player's audio session (third_party/video_player_android/README.md).
    // ignore: invalid_use_of_visible_for_testing_member
    final id = c.playerId;
    // ignore: invalid_use_of_visible_for_testing_member
    return id == VideoPlayerController.kUninitializedPlayerId ? null : id;
  }

  @override
  Future<void> initialize(String uri) async {
    try {
      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(uri));
      } else if (uri.startsWith('file://')) {
        _controller = VideoPlayerController.file(File.fromUri(Uri.parse(uri)));
      } else if (uri.startsWith('content://')) {
        _controller = VideoPlayerController.contentUri(Uri.parse(uri));
      } else {
        _controller = VideoPlayerController.file(File(uri));
      }

      await _controller!.initialize();

      _controller!.addListener(_onControllerUpdate);

      _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!_isDisposed && _controller != null && _controller!.value.isInitialized) {
          _positionController.add(_controller!.value.position);
        }
      });
    } catch (e) {
      _errorController.add('Failed to load video: $e');
      rethrow;
    }
  }

  void _onControllerUpdate() {
    if (_isDisposed || _controller == null) return;
    final value = _controller!.value;
    if (value.hasError) {
      _errorController.add(value.errorDescription);
    }
    // Only real changes: the controller notifies on every position tick.
    if (_lastPlaying != value.isPlaying) {
      _lastPlaying = value.isPlaying;
      _isPlayingController.add(value.isPlaying);
    }
    if (value.isCompleted && !_wasCompleted) {
      _completedController.add(null);
    }
    _wasCompleted = value.isCompleted;
    final caption = value.caption.text;
    if (caption != _lastCaption) {
      _lastCaption = caption;
      _captionController.add(caption);
    }
  }

  @override
  Future<void> play() async {
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
    _positionController.add(position);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Future<bool> setSubtitleFile(String? path) async {
    final c = _controller;
    if (c == null || _isDisposed) return false;
    if (path == null) {
      await c.setClosedCaptionFile(null);
      return true;
    }
    try {
      final bytes = await File(path).readAsBytes();
      // Subtitles are often saved in a legacy code page: never fail on bad bytes.
      final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
      final ClosedCaptionFile file =
          path.toLowerCase().endsWith('.vtt') ? WebVTTCaptionFile(text) : SubRipCaptionFile(text);
      if (file.captions.isEmpty) return false;
      if (_isDisposed) return false;
      await c.setClosedCaptionFile(Future<ClosedCaptionFile>.value(file));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<VideoAudioTrackInfo>> getAudioTracks() async {
    final c = _controller;
    if (c == null || _isDisposed || !c.value.isInitialized) return const [];
    try {
      if (!c.isAudioTrackSupportAvailable()) return const [];
      final tracks = await c.getAudioTracks();
      var n = 0;
      return [
        for (final t in tracks)
          VideoAudioTrackInfo(
            id: t.id,
            label: _trackLabel(t.label, t.language, ++n),
            isSelected: t.isSelected,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _trackLabel(String? label, String? language, int n) {
    if (label != null && label.trim().isNotEmpty) return label.trim();
    if (language != null && language.isNotEmpty && language != 'und') return language;
    return 'Track $n';
  }

  @override
  Future<void> selectAudioTrack(String id) async {
    final c = _controller;
    if (c == null || _isDisposed) return;
    try {
      await c.selectAudioTrack(id);
    } catch (_) {}
  }

  @override
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = c.value.size;

    switch (fit) {
      case BoxFit.cover:
      case BoxFit.fill:
        // Fill (crops the edges) or Stretch (ignores the aspect ratio).
        return SizedBox.expand(
          child: ClipRect(
            child: FittedBox(
              fit: fit,
              child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(c)),
            ),
          ),
        );
      case BoxFit.none:
        // Original: one video pixel per screen pixel, centred and cropped.
        return Builder(
          builder: (context) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            return ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: SizedBox(
                  width: size.width / dpr,
                  height: size.height / dpr,
                  child: VideoPlayer(c),
                ),
              ),
            );
          },
        );
      default:
        return Center(
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        );
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _positionTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;
    await _positionController.close();
    await _isPlayingController.close();
    await _errorController.close();
    await _completedController.close();
    await _captionController.close();
  }
}
