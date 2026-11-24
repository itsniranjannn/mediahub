import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../music_player/music_audio_handler.dart' show ExternalResumeItem;
import 'online_bridge_protocol.dart';
import 'online_media_session.dart';
import 'online_screen.dart' show OnlineAssets, onlineAssetsProvider;
import 'online_web_view.dart';

/// Where the page without a window was when the app came back on screen.
@immutable
class OnlineHeadlessHandBack {
  const OnlineHeadlessHandBack({required this.url, required this.position, required this.playing});

  /// The video's page, with its position (`t=`), for the Online tab to open.
  final Uri url;
  final Duration position;
  final bool playing;
}

/// [url] with the video's position as YouTube's `t=` (whole seconds; a page
/// that is not a video, or under two seconds in, is left as it is).
Uri onlineUrlAt(Uri url, Duration position) {
  final secs = position.inSeconds;
  if (secs < 2 || !url.queryParameters.containsKey('v')) return url;
  final q = Map<String, String>.of(url.queryParameters)..['t'] = '${secs}s';
  return url.replace(queryParameters: q);
}

/// Android: plays the Online video when there is no Activity at all.
///
/// The Online tab's WebView lives in the Activity's Flutter view. If the
/// process is ended while MediaHub's task is gone from recents (low memory,
/// a battery saver), a Play from the notification, the lock screen or
/// Bluetooth restarts only the media service: the restored notification
/// shows the last video but there is no window to build a WebView in. This
/// loads that video (at its saved position) in a WebView without a window,
/// on the application context, and wires it to the same media session, so
/// the controls play, pause, skip and seek it. When MediaHub comes back on
/// screen, [handBack] closes it and says where it was, for the Online tab to
/// carry on from there.
class OnlineHeadlessPlayer {
  OnlineHeadlessPlayer({
    required this.session,
    required OnlineHeadlessLauncher launch,
    required Future<OnlineAssets> Function() loadAssets,
    String Function() newToken = newOnlineBridgeToken,
  })  : _launch = launch, // ignore: prefer_initializing_formals
        _loadAssets = loadAssets, // ignore: prefer_initializing_formals
        _newToken = newToken; // ignore: prefer_initializing_formals

  final OnlineMediaSession session;
  final OnlineHeadlessLauncher _launch;
  final Future<OnlineAssets> Function() _loadAssets;
  final String Function() _newToken;

  OnlineHeadlessPage? _page;
  bool _starting = false;
  bool _disposed = false;
  int _generation = 0;

  /// A page without a window is playing or loading.
  bool get isActive => _page != null || _starting;

  /// Loads [item] without a window and plays it from its saved position.
  /// True once the page is running (it reports to [session] from then on).
  Future<bool> start(ExternalResumeItem item) async {
    if (_disposed) return false;
    if (isActive) return true;
    _starting = true;
    final generation = ++_generation;
    DiagnosticsService.instance.logEvent('online_headless_start');
    try {
      final assets = await _loadAssets();
      final token = _newToken();
      // The sender is in place before the page loads: its "ready" seeks
      // and plays (handoverOnNextPage) through it.
      session.attachSender((command) async {
        final page = _page;
        if (page == null || generation != _generation) return false;
        final r = await page.evaluateJavascript(command.toJavaScript());
        return r == true || r == 1 || r == 'true';
      });
      session.handoverOnNextPage(position: item.position, play: true, onHandover: () async {});
      final page = await _launch(
        url: item.resumeUri,
        bridgeScript: buildBridgeScript(assets.bridgeSource, token),
        fixtureHtml: assets.fixtureHtml,
        onBridgeMessage: (args) {
          if (generation != _generation) return;
          final message = parseBridgeMessage(args, token: token);
          if (message != null) session.handleMessage(message);
        },
      );
      if (generation != _generation || _disposed) {
        unawaited(page.dispose());
        return false;
      }
      _page = page;
      DiagnosticsService.instance.logEvent('online_headless_running');
      return true;
    } catch (e) {
      debugPrint('[Online] page without a window failed: $e');
      DiagnosticsService.instance.logEvent('online_headless_failed', {'error': e.runtimeType.toString()});
      if (generation == _generation) session.attachSender(null);
      return false;
    } finally {
      if (generation == _generation) _starting = false;
    }
  }

  /// MediaHub is on screen again: closes the page without a window and
  /// says where its video was (null when none is running). The media
  /// session stays with the video: the Online tab's page takes it over.
  OnlineHeadlessHandBack? handBack() {
    final page = _page;
    final wasStarting = _starting;
    if (page == null && !wasStarting) return null;
    _generation++;
    _page = null;
    _starting = false;
    final s = session.media.value;
    final position = session.estimatedPosition() ?? Duration.zero;
    session.attachSender(null);
    if (page != null) unawaited(page.dispose());
    DiagnosticsService.instance.logEvent('online_headless_handback', {'playing': s?.isPlaying ?? false});
    final url = s?.pageUrl;
    if (url == null) return null;
    return OnlineHeadlessHandBack(url: onlineUrlAt(url, position), position: position, playing: s?.isPlaying ?? false);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final page = _page;
    _page = null;
    if (page != null) unawaited(page.dispose());
  }
}

final onlineHeadlessPlayerProvider = Provider<OnlineHeadlessPlayer>((ref) {
  final player = OnlineHeadlessPlayer(
    session: ref.watch(onlineMediaSessionProvider),
    launch: launchInAppHeadlessPage,
    loadAssets: () => ref.read(onlineAssetsProvider.future),
  );
  ref.onDispose(player.dispose);
  return player;
});
