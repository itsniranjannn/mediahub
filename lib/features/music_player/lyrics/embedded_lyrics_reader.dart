// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads the lyrics stored inside a song file, in pure Dart (both phones).
///
/// Understands:
/// - ID3v2.3 / v2.4 at the start of the file (MP3): the `USLT` frame (text
///   in any of the four ID3 encodings), also an unsynchronised tag;
/// - MP4 / M4A: the iTunes `©lyr` item (`moov/udta/meta/ilst`);
/// - FLAC: the `LYRICS` or `UNSYNCEDLYRICS` Vorbis comment.
///
/// The file is never read whole: only the tag (at most [maxTagBytes]) or the
/// box headers and the `moov` box. Anything else, or a damaged file: null.
class EmbeddedLyricsReader {
  const EmbeddedLyricsReader();

  static const int maxTagBytes = 4 * 1024 * 1024;
  static const int _maxEntries = 2048;

  Future<String?> read(String path) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final length = await raf.length();
      final head = await _readAt(raf, 0, 12);
      if (head.length < 12) return null;
      if (_ascii(head, 0, 3) == 'ID3') return await _id3(raf, length);
      if (_ascii(head, 0, 4) == 'fLaC') return await _flac(raf, 4, length);
      if (_ascii(head, 4, 4) == 'ftyp') return await _mp4(raf, length);
      return null;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  static Future<Uint8List> _readAt(RandomAccessFile raf, int at, int count) async {
    await raf.setPosition(at);
    return raf.read(count);
  }

  static String _ascii(Uint8List b, int at, int n) =>
      at + n <= b.length ? String.fromCharCodes(b.sublist(at, at + n)) : '';

  static int _u32(Uint8List b, int at) => (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static int _syncsafe(Uint8List b, int at) =>
      ((b[at] & 0x7f) << 21) | ((b[at + 1] & 0x7f) << 14) | ((b[at + 2] & 0x7f) << 7) | (b[at + 3] & 0x7f);

  /// Removes ID3 unsynchronisation (0xFF 0x00 -> 0xFF).
  static Uint8List _resync(Uint8List data) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i++) {
      out.addByte(data[i]);
      if (data[i] == 0xff && i + 1 < data.length && data[i + 1] == 0) i++;
    }
    return out.takeBytes();
  }

  Future<String?> _id3(RandomAccessFile raf, int length) async {
    final header = await _readAt(raf, 0, 10);
    final major = header[3];
    if (major != 3 && major != 4) return null;
    final flags = header[5];
    final size = _syncsafe(header, 6);
    if (size <= 0 || size > maxTagBytes || size + 10 > length) return null;
    var body = await _readAt(raf, 10, size);
    final tagUnsync = flags & 0x80 != 0;
    if (major == 3 && tagUnsync) body = _resync(body);
    var pos = 0;
    if (flags & 0x40 != 0 && body.length >= 4) {
      // Extended header.
      pos = major == 4 ? _syncsafe(body, 0) : _u32(body, 0) + 4;
    }
    for (var i = 0; i < _maxEntries && pos + 10 <= body.length; i++) {
      final id = _ascii(body, pos, 4);
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
      final frameSize = major == 4 ? _syncsafe(body, pos + 4) : _u32(body, pos + 4);
      final formatFlags = body[pos + 9];
      final start = pos + 10;
      if (frameSize <= 0 || start + frameSize > body.length) break;
      if (id == 'USLT') {
        var data = Uint8List.sublistView(body, start, start + frameSize);
        if (major == 4 && (formatFlags & 0x02 != 0 || tagUnsync)) data = _resync(data);
        if (major == 4 && formatFlags & 0x01 != 0 && data.length > 4) data = Uint8List.sublistView(data, 4);
        final text = _uslt(data);
        if (text != null && text.trim().isNotEmpty) return text;
      }
      pos = start + frameSize;
    }
    return null;
  }

  /// USLT: encoding, 3-byte language, a description (terminated), the text.
  static String? _uslt(Uint8List data) {
    if (data.length < 5) return null;
    final enc = data[0];
    var at = 4;
    final wide = enc == 1 || enc == 2;
    // Skip the description.
    if (wide) {
      while (at + 1 < data.length && !(data[at] == 0 && data[at + 1] == 0)) {
        at += 2;
      }
      at += 2;
    } else {
      while (at < data.length && data[at] != 0) {
        at++;
      }
      at += 1;
    }
    if (at >= data.length) return null;
    return _decode(Uint8List.sublistView(data, at), enc);
  }

  static String _decode(Uint8List b, int enc) {
    switch (enc) {
      case 0:
        return latin1.decode(b).replaceAll('\u0000', '');
      case 3:
        return utf8.decode(b, allowMalformed: true).replaceAll('\u0000', '');
      default:
        // UTF-16 with a BOM (1) or big-endian (2).
        var bigEndian = enc == 2;
        var at = 0;
        if (b.length >= 2 && b[0] == 0xff && b[1] == 0xfe) {
          bigEndian = false;
          at = 2;
        } else if (b.length >= 2 && b[0] == 0xfe && b[1] == 0xff) {
          bigEndian = true;
          at = 2;
        }
        final units = <int>[];
        for (; at + 1 < b.length; at += 2) {
          final u = bigEndian ? (b[at] << 8) | b[at + 1] : (b[at + 1] << 8) | b[at];
          if (u == 0) continue;
          units.add(u);
        }
        return String.fromCharCodes(units);
    }
  }

  Future<String?> _flac(RandomAccessFile raf, int start, int length) async {
    var pos = start;
    for (var i = 0; i < 64 && pos + 4 <= length; i++) {
      final h = await _readAt(raf, pos, 4);
      if (h.length < 4) return null;
      final last = h[0] & 0x80 != 0;
      final type = h[0] & 0x7f;
      final size = (h[1] << 16) | (h[2] << 8) | h[3];
      if (type == 4 && size <= maxTagBytes) {
        final block = await _readAt(raf, pos + 4, size);
        return _vorbis(block);
      }
      if (last) return null;
      pos += 4 + size;
    }
    return null;
  }

  static int _le32(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

  static String? _vorbis(Uint8List b) {
    if (b.length < 8) return null;
    var at = 4 + _le32(b, 0);
    if (at + 4 > b.length) return null;
    final count = _le32(b, at);
    at += 4;
    String? unsynced;
    for (var i = 0; i < count && i < _maxEntries && at + 4 <= b.length; i++) {
      final len = _le32(b, at);
      at += 4;
      if (len < 0 || at + len > b.length) return null;
      final entry = utf8.decode(Uint8List.sublistView(b, at, at + len), allowMalformed: true);
      at += len;
      final eq = entry.indexOf('=');
      if (eq <= 0) continue;
      final key = entry.substring(0, eq).toUpperCase();
      final value = entry.substring(eq + 1);
      if (key == 'LYRICS' && value.trim().isNotEmpty) return value;
      if (key == 'UNSYNCEDLYRICS' && value.trim().isNotEmpty) unsynced = value;
    }
    return unsynced;
  }

  Future<String?> _mp4(RandomAccessFile raf, int length) async {
    final moov = await _child(raf, 0, length, 'moov');
    if (moov == null) return null;
    for (final path in const [
      ['udta', 'meta', 'ilst'],
      ['meta', 'ilst'],
    ]) {
      var range = moov;
      var ok = true;
      for (final name in path) {
        // "meta" is a full box: 4 bytes of version and flags before its children.
        final found = await _child(raf, range.$1, range.$2, name);
        if (found == null) {
          ok = false;
          break;
        }
        range = name == 'meta' ? (found.$1 + 4, found.$2) : found;
      }
      if (!ok) continue;
      final lyr = await _child(raf, range.$1, range.$2, '©lyr');
      if (lyr == null) continue;
      final data = await _child(raf, lyr.$1, lyr.$2, 'data');
      if (data == null) continue;
      final len = data.$2 - data.$1 - 8; // type + locale
      if (len <= 0 || len > maxTagBytes) continue;
      final bytes = await _readAt(raf, data.$1 + 8, len);
      return utf8.decode(bytes, allowMalformed: true);
    }
    return null;
  }

  /// The payload range (start, end) of the first [type] box between [start] and [end].
  Future<(int, int)?> _child(RandomAccessFile raf, int start, int end, String type) async {
    var pos = start;
    for (var i = 0; i < _maxEntries && pos + 8 <= end; i++) {
      final h = await _readAt(raf, pos, 16);
      if (h.length < 8) return null;
      var size = _u32(h, 0);
      final name = latin1.decode(h.sublist(4, 8));
      var header = 8;
      if (size == 1) {
        if (h.length < 16) return null;
        size = (_u32(h, 8) << 32) | _u32(h, 12);
        header = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) return null;
      if (name == type) return (pos + header, pos + size);
      pos += size;
    }
    return null;
  }
}
