import 'dart:convert';
import 'dart:math' as math;

import 'youtube_urls.dart';

/// Wire format between `assets/web/youtube_bridge.js` and Dart.
///
/// The page posts compact JSON objects through
/// `window.flutter_inappwebview.callHandler(onlineBridgeHandlerName, msg)`.
/// Every message carries the per-WebView token the script was injected with
/// (`t`); messages without it, with the wrong one, or with a page URL that is
/// not YouTube are dropped, so an iframe or another page cannot drive the
/// notification. Every field is clamped and trimmed before use.
const String onlineBridgeHandlerName = 'mediahubBridge';

/// Placeholder in the asset that Dart replaces with the session token.
const String onlineBridgeTokenPlaceholder = '__MEDIAHUB_BRIDGE_TOKEN__';

/// A fresh random token (32 hex characters) for one WebView.
String newOnlineBridgeToken([math.Random? random]) {
  final r = random ?? math.Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 16; i++) {
    sb.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// The bridge script with its token filled in. The token is hex only, so it
/// can never break out of the JS string literal it replaces.
String buildBridgeScript(String assetSource, String token) {
  if (!RegExp(r'^[0-9a-f]{16,64}$').hasMatch(token)) {
    throw ArgumentError.value(token, 'token', 'must be lowercase hex');
  }
  return assetSource.replaceAll(onlineBridgeTokenPlaceholder, token);
}

/// Playback status reported by the page.
enum OnlineMediaStatus { none, playing, paused, buffering, ended }

/// One snapshot of the page's main video, already validated.
class OnlineMediaState {
  const OnlineMediaState({
    required this.status,
    this.position = Duration.zero,
    this.duration,
    this.rate = 1.0,
    this.title = '',
    this.artist = '',
    this.artworkUrl,
    this.hasNext = false,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.pageUrl,
    this.event = '',
    this.pausedByPage = false,
    this.pausedBySystemControls = false,
  });

  final OnlineMediaStatus status;
  final Duration position;

  /// Null for live streams and before metadata loads.
  final Duration? duration;
  final double rate;
  final String title;

  /// Channel name.
  final String artist;

  /// https thumbnail on a YouTube image host, or null.
  final String? artworkUrl;

  /// The page exposes a "next" (media session handler or a next button).
  final bool hasNext;
  final int videoWidth;
  final int videoHeight;
  final Uri? pageUrl;

  /// The DOM event behind this snapshot ('play', 'pause', 'timeupdate', ...).
  final String event;

  /// A 'pause' the page made by itself: its own script paused the video with
  /// no touch or key from the user just before, and not on MediaHub's
  /// command (YouTube's idle "Continue watching?" stop looks like this). A
  /// pause from the browser itself (audio focus, a call) is never one.
  final bool pausedByPage;

  /// A 'pause' that came from the phone's own media controls through the
  /// browser (the iOS lock screen or Control Center): the user's choice.
  final bool pausedBySystemControls;

  bool get isPlaying => status == OnlineMediaStatus.playing || status == OnlineMediaStatus.buffering;

  /// This snapshot with another [status] (and the [event] that explains it).
  OnlineMediaState withStatus(OnlineMediaStatus status, {required String event}) => OnlineMediaState(
        status: status,
        position: position,
        duration: duration,
        rate: rate,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        hasNext: hasNext,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
        pageUrl: pageUrl,
        event: event,
        pausedByPage: pausedByPage,
        pausedBySystemControls: pausedBySystemControls,
      );

  String? get videoId => youTubeVideoId(pageUrl);

  /// Width / height of the video, clamped to what Android's picture-in-picture
  /// accepts (1:2.39 to 2.39:1); 16:9 when unknown.
  double get aspectRatio {
    if (videoWidth <= 0 || videoHeight <= 0) return 16 / 9;
    return (videoWidth / videoHeight).clamp(1 / 2.39, 2.39);
  }

  @override
  bool operator ==(Object other) =>
      other is OnlineMediaState &&
      other.status == status &&
      other.position == position &&
      other.duration == duration &&
      other.rate == rate &&
      other.title == title &&
      other.artist == artist &&
      other.artworkUrl == artworkUrl &&
      other.hasNext == hasNext &&
      other.videoWidth == videoWidth &&
      other.videoHeight == videoHeight &&
      other.pageUrl == pageUrl &&
      other.event == event &&
      other.pausedByPage == pausedByPage &&
      other.pausedBySystemControls == pausedBySystemControls;

  @override
  int get hashCode => Object.hash(status, position, duration, rate, title, artist, artworkUrl, hasNext,
      videoWidth, videoHeight, pageUrl, event, pausedByPage, pausedBySystemControls);

  @override
  String toString() => 'OnlineMediaState($status, ${position.inSeconds}s/${duration?.inSeconds}s, "$title")';
}

/// A message from the page.
sealed class BridgeMessage {
  const BridgeMessage();
}

/// The main video's state changed (or the 1 s timeupdate tick).
class BridgeMediaMessage extends BridgeMessage {
  const BridgeMediaMessage(this.state);
  final OnlineMediaState state;
}

/// The video entered or left the browser's own picture-in-picture (iOS).
class BridgePipMessage extends BridgeMessage {
  const BridgePipMessage(this.active);
  final bool active;
}

/// A video in the page entered or left fullscreen (the page's own fullscreen
/// events, or iOS's native video player). On iOS this, not the plugin's
/// window watch, decides whether the toolbar hides.
class BridgeFullscreenMessage extends BridgeMessage {
  const BridgeFullscreenMessage(this.active);
  final bool active;
}

/// The script is installed on a new document.
class BridgeReadyMessage extends BridgeMessage {
  const BridgeReadyMessage(this.pageUrl);
  final Uri? pageUrl;
}

const int _maxTitle = 300;
const int _maxArtist = 160;
const int _maxUrl = 2048;

String _text(Object? v, int max) {
  if (v is! String) return '';
  // Drop control characters, collapse whitespace, cap the length.
  final cleaned = v.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.length > max ? cleaned.substring(0, max) : cleaned;
}

double? _num(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  return null;
}

Duration _seconds(double s) => Duration(milliseconds: (s * 1000).round());

Uri? _youTubePageUrl(Object? v) {
  if (v is! String || v.length > _maxUrl) return null;
  final uri = Uri.tryParse(v);
  if (uri == null || uri.scheme != 'https' || !isYouTubePage(uri)) return null;
  return uri;
}

String? _artwork(Object? v) {
  if (v is! String || v.length > _maxUrl) return null;
  final uri = Uri.tryParse(v);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || !isYouTubeImageHost(uri.host)) {
    return null;
  }
  return uri.toString();
}

OnlineMediaStatus _status(Object? v) {
  switch (v) {
    case 'playing':
      return OnlineMediaStatus.playing;
    case 'paused':
      return OnlineMediaStatus.paused;
    case 'buffering':
      return OnlineMediaStatus.buffering;
    case 'ended':
      return OnlineMediaStatus.ended;
    default:
      return OnlineMediaStatus.none;
  }
}

/// Parses one handler call. [args] is what flutter_inappwebview passes to the
/// handler (the JS arguments list); the first argument is the message, as an
/// object or a JSON string. Returns null for anything invalid.
BridgeMessage? parseBridgeMessage(Object? args, {required String token}) {
  Object? raw = args;
  if (raw is List) raw = raw.isEmpty ? null : raw.first;
  if (raw is String) {
    if (raw.length > 8192) return null;
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  if (raw is! Map) return null;
  if (token.isEmpty || raw['t'] != token) return null;
  final pageUrl = _youTubePageUrl(raw['u']);
  // Only messages from a YouTube page in the main frame are accepted.
  if (pageUrl == null) return null;
  switch (raw['k']) {
    case 'ready':
      return BridgeReadyMessage(pageUrl);
    case 'pip':
      return BridgePipMessage(raw['on'] == true);
    case 'fs':
      return BridgeFullscreenMessage(raw['on'] == true);
    case 'media':
      final pos = (_num(raw['p']) ?? 0).clamp(0.0, 1e7);
      final dur = _num(raw['d']);
      final rate = (_num(raw['r']) ?? 1.0).clamp(0.0625, 16.0);
      final w = (_num(raw['vw']) ?? 0).clamp(0, 100000).round();
      final h = (_num(raw['vh']) ?? 0).clamp(0, 100000).round();
      final videoId = youTubeVideoId(pageUrl);
      return BridgeMediaMessage(OnlineMediaState(
        status: _status(raw['s']),
        position: _seconds(pos.toDouble()),
        duration: dur != null && dur > 0 && dur < 1e7 ? _seconds(dur) : null,
        rate: rate.toDouble(),
        title: _text(raw['ti'], _maxTitle),
        artist: _text(raw['ar'], _maxArtist),
        artworkUrl: _artwork(raw['aw']) ?? youTubeThumbnailFor(videoId),
        hasNext: raw['n'] == true,
        videoWidth: w,
        videoHeight: h,
        pageUrl: pageUrl,
        event: _text(raw['e'], 24),
        pausedByPage: raw['yp'] == true,
        pausedBySystemControls: raw['na'] == true,
      ));
  }
  return null;
}

/// Commands Dart sends to the page.
enum BridgeCommandKind {
  play,
  pause,
  seekTo,
  next,
  previous,
  setBackgroundPlay,
  setPipLayout,
  enterPip,
  setAutoPip,
  exitPip,
  exitFullscreen,
  search,
  requestState,
}

/// Longest search query sent to the page (the page refuses longer ones).
const int onlineMaxSearchQuery = 200;

class BridgeCommand {
  const BridgeCommand._(this.kind, [this.argument]);

  const BridgeCommand.play() : this._(BridgeCommandKind.play);
  const BridgeCommand.pause() : this._(BridgeCommandKind.pause);
  BridgeCommand.seekTo(Duration position) : this._(BridgeCommandKind.seekTo, position.inMilliseconds / 1000.0);
  const BridgeCommand.next() : this._(BridgeCommandKind.next);
  const BridgeCommand.previous() : this._(BridgeCommandKind.previous);
  const BridgeCommand.setBackgroundPlay(bool on) : this._(BridgeCommandKind.setBackgroundPlay, on);

  /// Android picture-in-picture: the playing video fills the page (an html class).
  const BridgeCommand.setPipLayout(bool on) : this._(BridgeCommandKind.setPipLayout, on);

  /// iOS: the browser's own picture-in-picture for the playing video.
  const BridgeCommand.enterPip() : this._(BridgeCommandKind.enterPip);
  const BridgeCommand.setAutoPip(bool on) : this._(BridgeCommandKind.setAutoPip, on);

  /// iOS: back from the browser's own picture-in-picture to the page.
  const BridgeCommand.exitPip() : this._(BridgeCommandKind.exitPip);

  /// Leaves the page's fullscreen (system Back).
  const BridgeCommand.exitFullscreen() : this._(BridgeCommandKind.exitFullscreen);

  /// Submits [query] in the page's own search (YouTube's single-page app).
  BridgeCommand.search(String query) : this._(BridgeCommandKind.search, _cleanQuery(query));
  const BridgeCommand.requestState() : this._(BridgeCommandKind.requestState);

  static String _cleanQuery(String q) {
    final cleaned = q.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.length > onlineMaxSearchQuery ? cleaned.substring(0, onlineMaxSearchQuery) : cleaned;
  }

  final BridgeCommandKind kind;
  final Object? argument;

  /// The JS to evaluate. The argument is a bool, a finite number or the
  /// user's own search text; text goes in as a JSON string literal (quotes,
  /// backslashes and line breaks escaped), so it can never end the literal.
  String toJavaScript() {
    final arg = argument;
    final String argJs;
    if (arg is bool) {
      argJs = arg ? 'true' : 'false';
    } else if (arg is num) {
      final v = arg.isFinite ? arg.clamp(0, 1e7) : 0;
      argJs = v.toString();
    } else if (arg is String) {
      // U+2028 / U+2029 are legal in JSON but ended JS string literals in
      // older engines: escaped as well.
      argJs = jsonEncode(arg).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    } else {
      argJs = 'null';
    }
    // Returns a value, so evaluateJavascript can tell whether the page had the bridge.
    return '(function(){try{var b=window.__mediahubBridge;'
        'return b?b.command(${jsonEncode(kind.name)},$argJs):false;}catch(e){return false;}})();';
  }

  @override
  bool operator ==(Object other) => other is BridgeCommand && other.kind == kind && other.argument == argument;

  @override
  int get hashCode => Object.hash(kind, argument);

  @override
  String toString() => 'BridgeCommand(${kind.name}${argument == null ? '' : ', $argument'})';
}
