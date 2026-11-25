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

  static bool _isKnownArtist(String? artist) {
    if (artist == null) return false;
    final lower = artist.trim().toLowerCase();
    return lower.isNotEmpty &&
        lower != 'local video' &&
        lower != 'unknown artist' &&
        lower != '<unknown>' &&
        lower != 'unknown';
  }

  /// Strips YouTube/filename noise (`Official Video`, `Full VIDEO song`, `| ...`,
  /// bracketed tags, quotes) so messy filenames still match LRCLIB search.
  static String cleanTitle(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    // Keep the song part before pipe separators ("Song | Movie | Artist").
    final pipe = s.indexOf('|');
    if (pipe > 0) s = s.substring(0, pipe);
    // Drop bracketed/parenthesized suffixes like (Official Video), [Lyrical], etc.
    s = s.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');
    // Drop common unbracketed YouTube suffixes.
    s = s.replaceAll(
      RegExp(
        r'\b(official\s+(music\s+|lyric(al)?\s+|audio\s+)?(video|audio|mv)|full\s+(video\s+)?song|(video|audio)\s+song|lyric(al)?(\s+video)?|hd\s+video|4k)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    // Trim quotes, dashes, and extra spaces.
    s = s.replaceAll('"', ' ').replaceAll("'", ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[-–—:\s]+|[-–—:\s]+$'), '').trim();
    return s;
  }

  /// The exact `/api/get` request for [item]; null when it has no usable title.
  static Uri? requestFor(MediaItem item) {
    final title = item.title.trim();
    if (title.isEmpty || title == 'Unknown Title') return null;
    final query = <String, String>{'track_name': title};
    final artist = item.artist?.trim();
    if (_isKnownArtist(artist)) query['artist_name'] = artist!;
    final album = item.album?.trim();
    if (album != null && album.isNotEmpty) query['album_name'] = album;
    if (item.durationMs > 0) query['duration'] = '${(item.durationMs / 1000).round()}';
    return Uri.https(host, '/api/get', query);
  }

  static String? _pickLyrics(Map<dynamic, dynamic> decoded) {
    final synced = decoded['syncedLyrics'];
    if (synced is String && synced.trim().isNotEmpty) return synced;
    final plain = decoded['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) return plain;
    return null;
  }

  /// The synced lyrics when LRCLIB has them, else the plain ones, else null.
  /// Tries exact `/api/get` first, then falls back to `/api/search` with a
  /// cleaned title so YouTube-style filenames also find lyrics.
  Future<String?> fetch(MediaItem item) async {
    final uri = requestFor(item);
    if (uri == null) return null;
    const headers = {
      'User-Agent': 'MediaHub (private family app)',
      'Accept': 'application/json',
    };
    final res = await _http.request(uri, headers: headers);
    if (res.finalUri.host != host) return null;
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.bodyText);
      if (decoded is Map) {
        final found = _pickLyrics(decoded);
        if (found != null) return found;
      }
    }

    // Fallback: search with cleaned title (handles YouTube-style filenames).
    final cleaned = cleanTitle(item.title);
    if (cleaned.isEmpty) return null;
    final searchUri = Uri.https(host, '/api/search', {'q': cleaned});
    final searchRes = await _http.request(searchUri, headers: headers);
    if (searchRes.finalUri.host != host || searchRes.statusCode != 200) return null;
    final list = jsonDecode(searchRes.bodyText);
    if (list is! List || list.isEmpty) return null;

    final targetSec = item.durationMs > 0 ? item.durationMs / 1000.0 : null;
    String? bestSynced;
    String? bestPlain;
    var bestSyncedDiff = double.infinity;
    var bestPlainDiff = double.infinity;

    for (final entry in list) {
      if (entry is! Map) continue;
      final dur = (entry['duration'] as num?)?.toDouble();
      final diff = (targetSec != null && dur != null) ? (dur - targetSec).abs() : 0.0;
      // Ignore matches whose length is far off when duration is known.
      if (targetSec != null && dur != null && diff > 25) continue;

      final synced = entry['syncedLyrics'];
      if (synced is String && synced.trim().isNotEmpty && diff < bestSyncedDiff) {
        bestSynced = synced;
        bestSyncedDiff = diff;
      }
      final plain = entry['plainLyrics'];
      if (plain is String && plain.trim().isNotEmpty && diff < bestPlainDiff) {
        bestPlain = plain;
        bestPlainDiff = diff;
      }
    }
    return bestSynced ?? bestPlain;
  }
}

/// The online lyrics cache's file name for [item] (`<sha1 of its id>.lrc`).
String lyricsCacheFileName(MediaItem item) => '${sha1.convert(utf8.encode(item.id))}.lrc';

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

  String _cacheKey(MediaItem item) => lyricsCacheFileName(item).replaceAll('.lrc', '');

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
        await pruneCache();
      }
    } catch (_) {}
    return Lyrics.parse(text, source: LyricsSource.online);
  }

  /// Most online lyrics kept on the phone; the oldest go first.
  static const int maxCachedLyrics = 500;

  /// Keeps the newest [maxCachedLyrics] files of the online lyrics cache.
  /// Never throws.
  Future<int> pruneCache({int keep = maxCachedLyrics}) async {
    var deleted = 0;
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return 0;
      final files = <(File, DateTime)>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is File && e.path.endsWith('.lrc')) {
          try {
            files.add((e, await e.lastModified()));
          } catch (_) {}
        }
      }
      if (files.length <= keep) return 0;
      files.sort((a, b) => b.$2.compareTo(a.$2));
      for (final (f, _) in files.skip(keep)) {
        try {
          await f.delete();
          deleted++;
        } catch (_) {}
      }
    } catch (_) {}
    return deleted;
  }

  /// Deletes [item]'s cached online lyrics (the song was deleted). Never throws.
  Future<void> forget(MediaItem item) async {
    _notOnline.remove(item.id);
    try {
      final f = File(p.join((await _cacheDir()).path, '${_cacheKey(item)}.lrc'));
      if (await f.exists()) await f.delete();
    } catch (_) {}
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
