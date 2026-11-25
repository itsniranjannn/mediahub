// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/diagnostics_service.dart';
import '../../../core/platform/phone_media.dart';
import '../../../core/security/safe_http_client.dart';
import '../../../core/storage/settings_store.dart';
import '../../../domain/models/media_item.dart';
import 'embedded_lyrics_reader.dart';
import 'lyrics.dart';

/// Settings → Lyrics → "Find lyrics online" (off by default: the song's
/// title, artist, album and length go to lrclib.net).
class OnlineLyricsNotifier extends Notifier<bool> {
  static const String prefKey = 'lyrics_online_lookup';

  static bool isOn() => SettingsStore.instance.getBool(prefKey);

  @override
  bool build() => isOn();

  void set(bool value) {
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
  }
}

final onlineLyricsProvider = NotifierProvider<OnlineLyricsNotifier, bool>(OnlineLyricsNotifier.new);

/// LRCLIB (https://lrclib.net, no account or key): `GET /api/get` with the
/// song's details. Only through [SafeHttpClient] (https, public addresses,
/// pinned DNS, 1 MB cap) and only to [host]: any other host, also after a
/// redirect, is refused.
class LrclibClient {
  LrclibClient({SafeHttpClient? http}) : _http = http ?? SafeHttpClient();

  final SafeHttpClient _http;

  static const String host = 'lrclib.net';

  /// The request for [item]; null when it has no usable title.
  static Uri? requestFor(MediaItem item) {
    final title = item.title.trim();
    if (title.isEmpty || title == 'Unknown Title') return null;
    final query = <String, String>{'track_name': title};
    final artist = item.artist?.trim();
    if (artist != null && artist.isNotEmpty && artist != 'Local Video') query['artist_name'] = artist;
    final album = item.album?.trim();
    if (album != null && album.isNotEmpty) query['album_name'] = album;
    if (item.durationMs > 0) query['duration'] = '${(item.durationMs / 1000).round()}';
    return Uri.https(host, '/api/get', query);
  }

  /// The synced lyrics when LRCLIB has them, else the plain ones, else null.
  Future<String?> fetch(MediaItem item) async {
    final uri = requestFor(item);
    if (uri == null) return null;
    final res = await _http.request(uri, headers: {
      'User-Agent': 'MediaHub (private family app)',
      'Accept': 'application/json',
    });
    if (res.finalUri.host != host) return null;
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.bodyText);
    if (decoded is! Map) return null;
    final synced = decoded['syncedLyrics'];
    if (synced is String && synced.trim().isNotEmpty) return synced;
    final plain = decoded['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) return plain;
    return null;
  }
}

/// Finds a song's lyrics: a `.lrc` file next to it first, then the lyrics
/// inside the file, then (only when the user turned it on) LRCLIB, whose
/// answer is kept on the phone so a song is looked up once.
class LyricsRepository {
  LyricsRepository({
    required PhoneMedia phoneMedia,
    LrclibClient? lrclib,
    EmbeddedLyricsReader reader = const EmbeddedLyricsReader(),
    bool Function()? onlineEnabled,
    Future<Directory> Function()? cacheDir,
  })  : _phone = phoneMedia,
        _lrclib = lrclib ?? LrclibClient(),
        _reader = reader, // ignore: prefer_initializing_formals
        _onlineEnabled = onlineEnabled ?? OnlineLyricsNotifier.isOn,
        _cacheDir = cacheDir ?? _defaultCacheDir;

  final PhoneMedia _phone;
  final LrclibClient _lrclib;
  final EmbeddedLyricsReader _reader;
  final bool Function() _onlineEnabled;
  final Future<Directory> Function() _cacheDir;

  /// Songs LRCLIB had nothing for, this session.
  final Set<String> _notOnline = {};

  static Future<Directory> _defaultCacheDir() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'lyrics'));

  Future<Lyrics?> find(MediaItem item) async {
    if (item.isOnline) return null;
    String? path;
    String? sidecar;
    if (item.uri.startsWith('content://')) {
      final found = await _phone.lyricsSidecar(item.uri);
      path = found.path;
      sidecar = found.lrc;
    } else if (!item.uri.contains('://')) {
      path = item.uri;
      sidecar = await _readSidecar(path);
    }
    if (sidecar != null) {
      final l = Lyrics.parse(sidecar, source: LyricsSource.sidecar);
      if (l != null) return l;
    }
    if (path != null) {
      final text = await _reader.read(path);
      if (text != null) {
        final l = Lyrics.parse(text, source: LyricsSource.embedded);
        if (l != null) return l;
      }
    }
    return _online(item);
  }

  static Future<String?> _readSidecar(String path) async {
    final base = p.withoutExtension(path);
    for (final ext in const ['.lrc', '.LRC']) {
      try {
        final f = File('$base$ext');
        if (await f.exists() && await f.length() <= 512 * 1024) return await f.readAsString();
      } catch (_) {}
    }
    return null;
  }

  String _cacheKey(MediaItem item) => sha1.convert(utf8.encode(item.id)).toString();

  Future<Lyrics?> _online(MediaItem item) async {
    File? cached;
    try {
      cached = File(p.join((await _cacheDir()).path, '${_cacheKey(item)}.lrc'));
      if (await cached.exists()) {
        return Lyrics.parse(await cached.readAsString(), source: LyricsSource.online);
      }
    } catch (_) {
      cached = null;
    }
    if (!_onlineEnabled() || _notOnline.contains(item.id)) return null;
    String? text;
    try {
      text = await _lrclib.fetch(item);
    } catch (e) {
      DiagnosticsService.instance.logEvent('lyrics_online_failed', {'type': e.runtimeType.toString()});
      return null;
    }
    if (text == null) {
      _notOnline.add(item.id);
      return null;
    }
    try {
      if (cached != null) {
        await cached.parent.create(recursive: true);
        await cached.writeAsString(text, flush: true);
      }
    } catch (_) {}
    return Lyrics.parse(text, source: LyricsSource.online);
  }
}

final lyricsRepositoryProvider =
    Provider<LyricsRepository>((ref) => LyricsRepository(phoneMedia: ref.watch(phoneMediaProvider)));

/// The current song's lyrics (null: none found).
final lyricsForProvider = FutureProvider.family<Lyrics?, MediaItem>((ref, item) {
  // A change of the online switch looks again.
  ref.watch(onlineLyricsProvider);
  return ref.watch(lyricsRepositoryProvider).find(item);
});
