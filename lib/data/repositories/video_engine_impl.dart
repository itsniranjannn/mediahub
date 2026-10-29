import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../domain/repositories/video_engine.dart';

class OfficialVideoEngine implements VideoEngine {
  VideoPlayerController? _controller;
  final _positionController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  Timer? _positionTimer;
  bool _isDisposed = false;

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
  Future<void> initialize(String uri) async {
    try {
      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(uri));
      } else if (uri.startsWith('content://') || uri.startsWith('file://')) {
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
    if (_controller!.value.hasError) {
      _errorController.add(_controller!.value.errorDescription);
    }
    _isPlayingController.add(_controller!.value.isPlaying);
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
  Widget buildPlayerWidget({BoxFit fit = BoxFit.contain}) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    if (fit == BoxFit.cover) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
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
  }
}
