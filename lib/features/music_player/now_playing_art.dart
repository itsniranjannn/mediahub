import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme/app_palette.dart';
import '../../core/services/artwork_service.dart';
import '../../domain/models/media_item.dart';
import '../../shared/widgets/artwork_placeholder.dart';

/// Cover art for the media session: the notification, the lock screen, the
/// Android 13+ quick-settings player and Bluetooth displays.
///
/// The system can only show a picture it can open itself: an http(s) URL or
/// a file. Phone songs have neither (their cover is embedded in the file or
/// kept by MediaStore), so their cover is read once through
/// [ArtworkService], written to `<cache>/np_art/` and handed over as a
/// `file://` uri. A song without any cover gets the same Bijuli placeholder
/// the app paints for it (its palette gradient and a note), rendered once
/// per gradient.
class NowPlayingArt {
  NowPlayingArt({
    Future<Directory?> Function()? cacheDirectory,
    Future<Uint8List?> Function(String uri)? embeddedArt,
    Future<Uint8List?> Function(String seed)? placeholder,
    this.maxCachedFiles = 200,
  })  : _cacheDirectory = cacheDirectory ?? _defaultCacheDirectory,
        _embeddedArt = embeddedArt ?? _defaultEmbeddedArt,
        _placeholder = placeholder ?? renderPlaceholderPng;

  /// Edge of the covers handed to the system, in pixels.
  static const int artSize = 512;

  /// Folder under the cache directory.
  static const String folderName = 'np_art';

  /// Covers kept on disk before the oldest are removed.
  final int maxCachedFiles;

  final Future<Directory?> Function() _cacheDirectory;
  final Future<Uint8List?> Function(String uri) _embeddedArt;
  final Future<Uint8List?> Function(String seed) _placeholder;

  /// Song id -> the file handed to the system.
  final Map<String, Uri> _known = {};

  /// Songs that got the placeholder, with the [ArtworkService.negativeGeneration]
  /// of that answer (a rescan may find a cover later).
  final Map<String, int> _placeholderGeneration = {};
  final Map<String, Future<Uri?>> _inFlight = {};
  Future<Directory?>? _directory;
  int _writesSincePrune = 0;

  static Future<Directory?> _defaultCacheDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return null; // no path_provider (tests, unsupported platform)
    }
  }

  static Future<Uint8List?> _defaultEmbeddedArt(String uri) =>
      ArtworkService.instance.getArtwork(uri, size: artSize);

  /// The picture the system can open without a lookup: the online
  /// thumbnail or the image saved with a download. Null for phone songs.
  static Uri? directUri(MediaItem item) {
    final path = item.artworkPath;
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http://') || path.startsWith('https://') ? Uri.parse(path) : Uri.file(path);
  }

  /// What is known for [item] right now, without waiting: its direct
  /// picture or a cover resolved earlier. Null when [resolve] has to run.
  Uri? peek(MediaItem item) {
    final direct = directUri(item);
    if (direct != null) return direct;
    final known = _known[item.id];
    if (known == null) return null;
    final generation = _placeholderGeneration[item.id];
    if (generation != null && generation != ArtworkService.instance.negativeGeneration) {
      // The library was rescanned since: look for a real cover again.
      _known.remove(item.id);
      _placeholderGeneration.remove(item.id);
      return null;
    }
    return known;
  }

  /// A `file://` (or http) uri for [item]'s cover, or for its placeholder
  /// when it has none. Null only when nothing can be written (no cache
  /// folder). Concurrent calls for one song share the work.
  Future<Uri?> resolve(MediaItem item) {
    final now = peek(item);
    if (now != null) return Future.value(now);
    final running = _inFlight[item.id];
    if (running != null) return running;
    final future = _resolve(item);
    _inFlight[item.id] = future;
    future.whenComplete(() => _inFlight.remove(item.id));
    return future;
  }

  /// A file name safe on every file system and unique per id.
  @visibleForTesting
  static String fileNameFor(String id) {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final short = safe.length > 80 ? safe.substring(0, 80) : safe;
    return '${short}_${ArtworkPlaceholder.hashOf(id).toRadixString(16)}.jpg';
  }

  Future<Directory?> _artDirectory() => _directory ??= () async {
        final base = await _cacheDirectory();
        if (base == null) return null;
        final dir = Directory('${base.path}${Platform.pathSeparator}$folderName');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }();

  Future<Uri?> _resolve(MediaItem item) async {
    try {
      final dir = await _artDirectory();
      if (dir == null) {
        _directory = null; // try again next time
        return null;
      }
      final file = File('${dir.path}${Platform.pathSeparator}${fileNameFor(item.id)}');
      if (await file.exists() && await file.length() > 0) {
        return _known[item.id] = Uri.file(file.path);
      }

      Uint8List? bytes;
      try {
        bytes = await _embeddedArt(item.uri);
      } catch (_) {
        bytes = null;
      }
      if (bytes != null && bytes.isNotEmpty) {
        await _writeAtomically(file, bytes);
        _placeholderGeneration.remove(item.id);
        return _known[item.id] = Uri.file(file.path);
      }

      // No cover: the song's placeholder, one file per palette gradient.
      final generation = ArtworkService.instance.negativeGeneration;
      final index = ArtworkPlaceholder.paletteIndexFor(item.uri);
      final placeholder = File('${dir.path}${Platform.pathSeparator}placeholder_$index.png');
      if (!await placeholder.exists() || await placeholder.length() == 0) {
        final png = await _placeholder(item.uri);
        if (png == null || png.isEmpty) return null;
        await _writeAtomically(placeholder, png);
      }
      _placeholderGeneration[item.id] = generation;
      return _known[item.id] = Uri.file(placeholder.path);
    } catch (e) {
      debugPrint('[NowPlayingArt] could not resolve art: $e');
      return null;
    }
  }

  /// Written next to the target and renamed, so the system never reads a
  /// half-written picture.
  Future<void> _writeAtomically(File target, Uint8List bytes) async {
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
    if (++_writesSincePrune >= 20) {
      _writesSincePrune = 0;
      unawaited(_prune(target.parent));
    }
  }

  /// Keeps the newest [maxCachedFiles] covers (placeholders always stay).
  Future<void> _prune(Directory dir) async {
    try {
      final covers = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jpg')) covers.add(entity);
      }
      if (covers.length <= maxCachedFiles) return;
      final stamped = <(File, DateTime)>[];
      for (final f in covers) {
        stamped.add((f, await f.lastModified()));
      }
      stamped.sort((a, b) => a.$2.compareTo(b.$2));
      final keep = _known.values.map((u) => u.toFilePath()).toSet();
      for (final (file, _) in stamped.take(stamped.length - maxCachedFiles)) {
        if (keep.contains(file.path)) continue;
        await file.delete();
      }
    } catch (_) {
      // best effort
    }
  }
}

/// The [ArtworkPlaceholder] look for [seed] as a square PNG: the palette
/// gradient of the ink theme, the soft top-left highlight, the two faint
/// rings and a white note in the middle.
Future<Uint8List?> renderPlaceholderPng(String seed, {int size = NowPlayingArt.artSize}) async {
  final side = size.toDouble();
  final rect = Rect.fromLTWH(0, 0, side, side);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, rect);
  final gradient = ArtworkPlaceholder.gradientFor(seed, AppPalette.dark);
  canvas
    ..drawRect(rect, Paint()..shader = gradient.createShader(rect))
    ..drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topLeft,
          radius: 1.1,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = (side * 0.025).clamp(1.0, 12.0)
    ..color = const Color(0x14FFFFFF);
  for (final r in const [0.42, 0.74]) {
    canvas.drawCircle(rect.bottomRight, side * r, ring);
  }

  const icon = Icons.music_note_rounded;
  final glyph = side * ArtworkPlaceholder.glyphFraction;
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: glyph,
        height: 1,
        color: Colors.white.withValues(alpha: ArtworkPlaceholder.glyphOpacity),
        shadows: [Shadow(color: const Color(0x40000000), blurRadius: side / 48, offset: Offset(0, side / 96))],
      ),
    ),
  )..layout();
  painter.paint(canvas, Offset((side - painter.width) / 2, (side - painter.height) / 2));
  painter.dispose();

  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(size, size);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    picture.dispose();
  }
}
