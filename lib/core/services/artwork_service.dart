import 'dart:async';
import 'package:flutter/services.dart';

class ArtworkService {
  static const MethodChannel _channel = MethodChannel('mediahub/media_store');
  static final ArtworkService instance = ArtworkService._();
  ArtworkService._();

  // In-memory bounded LRU cache (max ~30 MB = 30 * 1024 * 1024 bytes)
  static const int _maxByteSize = 30 * 1024 * 1024;
  int _currentByteSize = 0;
  final Map<String, Uint8List> _cache = {};

  // Negative lookup cache (set of cacheKeys known to have no artwork)
  final Set<String> _negativeCache = {};

  // In-flight deduplication map
  final Map<String, Future<Uint8List?>> _inFlight = {};

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
        final bytes = Uint8List.fromList(raw.cast<int>());
        _addToCache(cacheKey, bytes);
        return bytes;
      }
    } catch (_) {
      // Ignore
    }

    // Cache negative lookup (keep negative cache bounded to 1000 entries)
    if (_negativeCache.length >= 1000) {
      _negativeCache.remove(_negativeCache.first);
    }
    _negativeCache.add(cacheKey);
    return null;
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

  void clearCache() {
    _cache.clear();
    _negativeCache.clear();
    _inFlight.clear();
    _currentByteSize = 0;
  }
}
