// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform_info.dart';
import 'embedded_cover_reader.dart';

class ArtworkService {
  static const MethodChannel _channel = MethodChannel('mediahub/media_store');
  static final ArtworkService instance = ArtworkService._();
  ArtworkService._();

  /// iPhone: the folders whose files may be read for an embedded cover
  /// (MediaHub's own files). Tests set it; production asks path_provider.
  @visibleForTesting
  static Future<List<String>> Function()? debugAppFolders;

  /// Reads covers out of downloaded files on iPhone.
  static const EmbeddedCoverReader _coverReader = EmbeddedCoverReader();

  /// iPhone: how long scaling a cover may take. After that the cover is
  /// handed over as it is (and not cached), so the lock screen never waits
  /// on it: in the background iOS gives Flutter no GPU, and reading a scaled
  /// picture back would wait until the app is opened again.
  @visibleForTesting
  static Duration scaleTimeout = const Duration(seconds: 3);

  // In-memory bounded LRU cache (max ~30 MB = 30 * 1024 * 1024 bytes)
  static const int _maxByteSize = 30 * 1024 * 1024;
  int _currentByteSize = 0;
  final Map<String, Uint8List> _cache = {};

  // Negative lookup cache (set of cacheKeys known to have no artwork)
  final Set<String> _negativeCache = {};

  // In-flight deduplication map
  final Map<String, Future<Uint8List?>> _inFlight = {};

  /// iPhone: MediaHub's folders, resolved once (see [debugAppFolders]).
  Future<List<String>>? _appFolders;

  /// Artwork already in the memory cache for [uri] at [size], without a
  /// platform call; null when it has not been loaded (or there is none).
  /// Lets a thumbnail scrolled back into view paint its cover on the first
  /// frame instead of flashing its placeholder.
  Uint8List? peek(String uri, {int size = 256}) => _cache['$uri@$size'];

  /// Whether a real cover for [uri] is already in memory at any size.
  bool hasCached(String uri) {
    final prefix = '$uri@';
    for (final key in _cache.keys) {
      // Only "<uri>@<size>": a longer uri that contains "@" is another song.
      if (key.startsWith(prefix) && int.tryParse(key.substring(prefix.length)) != null) {
        return true;
      }
    }
    return false;
  }

  /// Whether a lookup for [uri] at [size] already found no artwork, so the
  /// answer is known without waiting for [getArtwork].
  bool isKnownMissing(String uri, {int size = 256}) => _negativeCache.contains('$uri@$size');

  Future<Uint8List?> getArtwork(String uri, {int size = 256}) async {
    final cacheKey = '$uri@$size';

    // 1. Check positive LRU cache
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache.remove(cacheKey)!;
      _cache[cacheKey] = cached; // re-insert as most recently used
      return cached;
    }

    // 2. Check negative cache
    if (_negativeCache.contains(cacheKey)) {
      return null;
    }

    // 3. De-duplicate in-flight requests
    if (_inFlight.containsKey(cacheKey)) {
      return _inFlight[cacheKey];
    }

    final future = _fetchArtwork(cacheKey, uri, size);
    _inFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<Uint8List?> _fetchArtwork(String cacheKey, String uri, int size) async {
    // The 'mediahub/media_store' channel is Android only: on iPhone the
    // cover comes from the downloaded file itself.
    if (PlatformInfo.isIOS) {
      final cover = await _embeddedCover(uri, size);
      if (cover != null) {
        // A cover that could not be scaled is used once, not kept: the next
        // lookup (with the app open) scales it.
        if (cover.scaled) _addToCache(cacheKey, cover.bytes);
        return cover.bytes;
      }
    } else {
      final bytes = await _fromChannel(uri, size);
      if (bytes != null) {
        _addToCache(cacheKey, bytes);
        return bytes;
      }
    }

    // Cache negative lookup (keep negative cache bounded to 1000 entries)
    if (_negativeCache.length >= 1000) {
      _negativeCache.remove(_negativeCache.first);
    }
    _negativeCache.add(cacheKey);
    return null;
  }

  /// Android: MediaStore's thumbnail, the embedded cover or a video frame.
  Future<Uint8List?> _fromChannel(String uri, int size) async {
    try {
      final List<dynamic>? raw = await _channel.invokeMethod<List<dynamic>>(
        'getArtwork',
        {
          'uri': uri,
          'width': size,
          'height': size,
        },
      );
      if (raw != null) {
        return Uint8List.fromList(raw.cast<int>());
      }
    } catch (_) {
      // Ignore
    }
    return null;
  }

  /// iPhone: the cover embedded in a file MediaHub keeps in its own folders
  /// (a downloaded MP3, M4A or FLAC), scaled for [size]. Null for anything
  /// else: web links, content:// uris, files outside MediaHub's folders.
  /// [scaled] is false when the cover comes as it is because it could not be
  /// scaled now (the app is in the background, or scaling took too long).
  Future<({Uint8List bytes, bool scaled})?> _embeddedCover(String uri, int size) async {
    try {
      final path = _localPath(uri);
      if (path == null) return null;
      final real = await File(path).resolveSymbolicLinks();
      final folders = await (_appFolders ??= _loadAppFolders());
      if (!folders.any((folder) => p.isWithin(folder, real))) return null;
      final picture = await _coverReader.read(real);
      if (picture == null) return null;
      if (_inBackground) return (bytes: picture, scaled: false);
      var timedOut = false;
      final fitted = await _fitToSize(picture, size).timeout(scaleTimeout, onTimeout: () {
        timedOut = true;
        return picture;
      });
      if (fitted == null) return null;
      return (bytes: fitted, scaled: !timedOut);
    } catch (_) {
      return null;
    }
  }

  /// Whether the app is in the background now (for example the lock screen
  /// asking for the next song's cover), where iOS lets Flutter use no GPU.
  static bool get _inBackground {
    try {
      return switch (SchedulerBinding.instance.lifecycleState) {
        ui.AppLifecycleState.hidden || ui.AppLifecycleState.paused || ui.AppLifecycleState.detached => true,
        _ => false,
      };
    } catch (_) {
      return false; // no binding yet
    }
  }

  /// The file path in [uri] (a plain absolute path or a file:// uri), or null.
  static String? _localPath(String uri) {
    if (uri.startsWith('file://')) {
      final path = Uri.parse(uri).toFilePath();
      return p.isAbsolute(path) ? path : null;
    }
    if (uri.contains('://')) return null; // content://, https:// ...
    return p.isAbsolute(uri) ? uri : null;
  }

  Future<List<String>> _loadAppFolders() async {
    try {
      final hook = debugAppFolders;
      final folders = hook != null
          ? await hook()
          : [
              (await getApplicationDocumentsDirectory()).path,
              (await getApplicationSupportDirectory()).path,
            ];
      final resolved = <String>[];
      for (final folder in folders) {
        try {
          resolved.add(await Directory(folder).resolveSymbolicLinks());
        } catch (_) {
          // Not there (yet): nothing inside it to read.
        }
      }
      return resolved;
    } catch (_) {
      _appFolders = null; // try again next time
      return const [];
    }
  }

  /// [picture] as is when it is small enough for [size]; otherwise scaled so
  /// its longer side is [size] (a PNG), so a list row never decodes a
  /// 3000 px cover. Null when it does not decode.
  static Future<Uint8List?> _fitToSize(Uint8List picture, int size) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(picture);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      final longest = math.max(width, height);
      if (longest <= 0) return null;
      if (longest <= size * 2) return picture;
      final scale = size / longest;
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  void _addToCache(String key, Uint8List bytes) {
    // Fix size accounting when a key is overwritten
    if (_cache.containsKey(key)) {
      final existing = _cache.remove(key);
      if (existing != null) {
        _currentByteSize -= existing.lengthInBytes;
      }
    }

    while (_currentByteSize + bytes.lengthInBytes > _maxByteSize && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _currentByteSize -= removed.lengthInBytes;
      }
    }

    _cache[key] = bytes;
    _currentByteSize += bytes.lengthInBytes;
  }

  /// Bumped whenever the "no artwork" answers are forgotten, so callers that
  /// remembered a placeholder for a song (the media notification) look again.
  int get negativeGeneration => _negativeGeneration;
  int _negativeGeneration = 0;

  /// Forgets which songs had no artwork, keeping the covers already loaded.
  /// Call after a library rescan: a song may have gained a cover since.
  void clearNegativeCache() {
    _negativeCache.clear();
    _negativeGeneration++;
  }

  void clearCache() {
    _cache.clear();
    _negativeCache.clear();
    _inFlight.clear();
    _currentByteSize = 0;
    _negativeGeneration++;
    _appFolders = null;
  }
}
