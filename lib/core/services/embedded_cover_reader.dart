// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads the cover picture embedded in a song file, in pure Dart.
///
/// The iPhone app has no native artwork lookup (Android asks MediaStore), so
/// [ArtworkService] uses this for the files MediaHub downloaded itself.
///
/// Understands:
/// - an ID3v2.3 or ID3v2.4 tag at the start of the file (MP3, and some other
///   files): the `APIC` frame, the front cover when there are several, also
///   when the tag or the frame is unsynchronised;
/// - MP4 / M4A: the iTunes `covr` item (`moov/udta/meta/ilst/covr/data`, or
///   `moov/meta/ilst/...`);
/// - FLAC: the `PICTURE` metadata block, also after a leading ID3 tag.
///
/// Only JPEG and PNG pictures are returned, and none larger than
/// [maxPictureBytes]. The file is never read whole: only the tag headers,
/// box headers and the picture itself, by seeking. Anything it does not
/// understand, or a damaged file, gives null.
class EmbeddedCoverReader {
  const EmbeddedCoverReader({this.maxPictureBytes = defaultMaxPictureBytes});

  /// Covers are rarely over 2 MB; a 3000 px PNG can reach about 8.
  static const int defaultMaxPictureBytes = 8 * 1024 * 1024;

  /// Pictures larger than this are skipped.
  final int maxPictureBytes;

  /// Bounds every loop over frames, blocks and boxes (a damaged file cannot
  /// make it spin).
  static const int _maxEntries = 1024;

  /// Pictures read before giving up on finding a front cover.
  static const int _maxPictures = 4;

  /// The ID3 picture type of the front cover (FLAC uses the same numbers).
  static const int _frontCover = 3;

  /// An ID3v2.3 / v2.4 frame id: four capital letters or digits.
  static final RegExp _frameId = RegExp(r'^[A-Z0-9]{4}$');

  /// The embedded cover of the file at [path], or null.
  Future<Uint8List?> read(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final source = _FileSource(file, await file.length());
      final head = await source.read(0, 12);
      if (head.length < 12) return null;

      if (_ascii(head, 0, 3) == 'ID3') {
        final (picture, tagEnd) = await _id3(source);
        if (picture != null) return picture;
        if (tagEnd == null) return null;
        // A FLAC file with an ID3 tag in front of it.
        final next = await source.read(tagEnd, 4);
        if (next.length == 4 && _ascii(next, 0, 4) == 'fLaC') return await _flac(source, tagEnd + 4);
        return null;
      }
      if (_ascii(head, 0, 4) == 'fLaC') return await _flac(source, 4);
      if (_ascii(head, 4, 8) == 'ftyp') return await _mp4(source);
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await file?.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // ID3v2
  // ---------------------------------------------------------------------------

  /// The picture in the ID3 tag at the start of [file], and where the tag
  /// ends (null when the header is not a valid ID3v2 header).
  Future<(Uint8List?, int?)> _id3(_Source file) async {
    final header = await file.read(0, 10);
    if (header.length < 10) return (null, null);
    final major = header[3];
    final flags = header[5];
    final size = _syncSafe(header, 6);
    if (size == null) return (null, null);
    final hasFooter = major == 4 && flags & 0x10 != 0;
    final tagEnd = 10 + size + (hasFooter ? 10 : 0);
    if (major != 3 && major != 4) return (null, tagEnd);

    final tagUnsync = flags & 0x80 != 0;
    _Source body;
    if (major == 3 && tagUnsync) {
      // ID3v2.3 unsynchronises the whole tag, frame headers too: undo it in
      // memory (the tag is mostly the picture itself, so it is capped alike).
      if (size > maxPictureBytes + 64 * 1024) return (null, tagEnd);
      body = _MemorySource(_resync(await file.read(10, size)));
    } else {
      body = _OffsetSource(file, 10, size);
    }

    var pos = 0;
    if (flags & 0x40 != 0) {
      // Extended header: v2.3 gives its size without the 4 size bytes,
      // v2.4 as a sync-safe number that includes them.
      final ext = await body.read(0, 4);
      if (ext.length < 4) return (null, tagEnd);
      final extSize = major == 3 ? _be32(ext, 0) + 4 : _syncSafe(ext, 0);
      if (extSize == null) return (null, tagEnd);
      pos = extSize;
    }

    Uint8List? firstPicture;
    var pictures = 0;
    for (var i = 0; i < _maxEntries && pos + 10 <= body.length; i++) {
      final frame = await body.read(pos, 10);
      if (frame.length < 10 || frame[0] == 0) break; // padding
      final id = _ascii(frame, 0, 4);
      if (!_frameId.hasMatch(id)) break;
      var frameSize = major == 4 ? _syncSafe(frame, 4) : _be32(frame, 4);
      if (major == 4) {
        // Some v2.4 writers (old iTunes among them) store plain sizes. When
        // the sync-safe size does not end on the next frame and the plain
        // one does, the plain one is right.
        final plain = _be32(frame, 4);
        if (plain != frameSize &&
            (frameSize == null || !await _endsAtFrameBoundary(body, pos + 10 + frameSize)) &&
            await _endsAtFrameBoundary(body, pos + 10 + plain)) {
          frameSize = plain;
        }
      }
      if (frameSize == null || pos + 10 + frameSize > body.length) break;

      if (id == 'APIC' && frameSize <= maxPictureBytes + 64 * 1024) {
        final data = await _frameData(body, pos + 10, frameSize, frame[9], major, tagUnsync);
        if (data != null) {
          final (type, picture) = _apic(data);
          if (picture != null) {
            if (type == _frontCover) return (picture, tagEnd);
            firstPicture ??= picture;
          }
        }
        if (++pictures >= _maxPictures) break;
      }
      pos += 10 + frameSize;
    }
    return (firstPicture, tagEnd);
  }

  /// Whether a frame ending at [end] is followed by another frame, by
  /// padding or by the end of the tag (a wrong frame size lands elsewhere).
  Future<bool> _endsAtFrameBoundary(_Source body, int end) async {
    if (end > body.length) return false;
    if (end + 10 > body.length) return true; // the end, or padding too short for a frame
    final next = await body.read(end, 4);
    if (next.length < 4) return true;
    return next[0] == 0 || _frameId.hasMatch(_ascii(next, 0, 4));
  }

  /// A frame's data with its format flags applied, or null for compressed
  /// and encrypted frames (covers are never stored that way in practice).
  Future<Uint8List?> _frameData(_Source body, int at, int size, int formatFlags, int major, bool tagUnsync) async {
    var data = await body.read(at, size);
    if (data.length < size) return null;
    if (major == 3) {
      if (formatFlags & 0xC0 != 0) return null; // compressed, encrypted
      if (formatFlags & 0x20 != 0) data = Uint8List.sublistView(data, 1); // group id
      return data;
    }
    if (formatFlags & 0x0C != 0) return null; // compressed, encrypted
    var skip = 0;
    if (formatFlags & 0x40 != 0) skip += 1; // group id
    if (formatFlags & 0x01 != 0) skip += 4; // data length indicator
    if (skip > data.length) return null;
    data = Uint8List.sublistView(data, skip);
    if (tagUnsync || formatFlags & 0x02 != 0) data = _resync(data);
    return data;
  }

  /// The picture type and the picture of an APIC frame's data.
  (int, Uint8List?) _apic(Uint8List data) {
    if (data.length < 4) return (-1, null);
    final encoding = data[0];
    final mimeEnd = data.indexOf(0, 1);
    if (mimeEnd < 0 || mimeEnd + 2 > data.length) return (-1, null);
    final mime = latin1.decode(Uint8List.sublistView(data, 1, mimeEnd), allowInvalid: true);
    if (mime == '-->') return (-1, null); // a link, not a picture
    final type = data[mimeEnd + 1];
    final descStart = mimeEnd + 2;
    var pictureStart = -1;
    if (encoding == 1 || encoding == 2) {
      // UTF-16: the description ends with two zero bytes on a character
      // boundary.
      for (var i = descStart; i + 1 < data.length; i += 2) {
        if (data[i] == 0 && data[i + 1] == 0) {
          pictureStart = i + 2;
          break;
        }
      }
    } else {
      final end = data.indexOf(0, descStart);
      if (end >= 0) pictureStart = end + 1;
    }
    if (pictureStart < 0 || pictureStart >= data.length) return (type, null);
    return (type, _image(Uint8List.sublistView(data, pictureStart)));
  }

  // ---------------------------------------------------------------------------
  // FLAC
  // ---------------------------------------------------------------------------

  /// The picture among the FLAC metadata blocks starting at [start].
  Future<Uint8List?> _flac(_Source file, int start) async {
    var pos = start;
    Uint8List? firstPicture;
    var pictures = 0;
    for (var i = 0; i < _maxEntries; i++) {
      final header = await file.read(pos, 4);
      if (header.length < 4) break;
      final last = header[0] & 0x80 != 0;
      final type = header[0] & 0x7F;
      final length = (header[1] << 16) | (header[2] << 8) | header[3];
      if (type == 127) break; // invalid
      if (type == 6 && length <= maxPictureBytes + 64 * 1024) {
        final block = await file.read(pos + 4, length);
        final (pictureType, picture) = _flacPicture(block);
        if (picture != null) {
          if (pictureType == _frontCover) return picture;
          firstPicture ??= picture;
        }
        if (++pictures >= _maxPictures) break;
      }
      if (last) break;
      pos += 4 + length;
    }
    return firstPicture;
  }

  /// The picture type and the picture of a FLAC PICTURE block.
  (int, Uint8List?) _flacPicture(Uint8List block) {
    var at = 0;
    int? next32() {
      if (at + 4 > block.length) return null;
      final value = _be32(block, at);
      at += 4;
      return value;
    }

    final type = next32();
    final mimeLength = next32();
    if (type == null || mimeLength == null) return (-1, null);
    at += mimeLength;
    final descLength = next32();
    if (descLength == null) return (type, null);
    at += descLength + 16; // width, height, colour depth, colours used
    final dataLength = next32();
    if (dataLength == null || at + dataLength > block.length) return (type, null);
    return (type, _image(Uint8List.sublistView(block, at, at + dataLength)));
  }

  // ---------------------------------------------------------------------------
  // MP4
  // ---------------------------------------------------------------------------

  /// The `covr` picture of an MP4 / M4A file.
  Future<Uint8List?> _mp4(_Source file) async {
    final moov = await _child(file, 0, file.length, 'moov');
    if (moov == null) return null;
    for (final path in const [
      ['udta', 'meta'],
      ['meta'],
    ]) {
      var box = moov;
      for (final name in path) {
        final found = await _child(file, box.$1, box.$2, name);
        if (found == null) {
          box = (-1, -1);
          break;
        }
        box = found;
      }
      if (box.$1 < 0) continue;
      final picture = await _mp4MetaCover(file, box);
      if (picture != null) return picture;
    }
    return null;
  }

  /// The cover inside a `meta` box ([meta] is its content range).
  Future<Uint8List?> _mp4MetaCover(_Source file, (int, int) meta) async {
    // iTunes writes `meta` as a full box (4 bytes of version and flags before
    // its children); QuickTime files do not. Its first child is `hdlr`.
    final peek = await file.read(meta.$1, 8);
    if (peek.length < 8) return null;
    final childrenStart = _ascii(peek, 4, 8) == 'hdlr' ? meta.$1 : meta.$1 + 4;
    final ilst = await _child(file, childrenStart, meta.$2, 'ilst');
    if (ilst == null) return null;
    final covr = await _child(file, ilst.$1, ilst.$2, 'covr');
    if (covr == null) return null;

    var pos = covr.$1;
    for (var i = 0; i < _maxPictures && pos < covr.$2; i++) {
      final data = await _child(file, pos, covr.$2, 'data');
      if (data == null) break;
      // Type indicator (4 bytes: 13 JPEG, 14 PNG) and locale (4), then the
      // picture. The type is not trusted: the picture's own bytes decide.
      final pictureLength = data.$2 - data.$1 - 8;
      if (pictureLength > 0 && pictureLength <= maxPictureBytes) {
        final picture = _image(await file.read(data.$1 + 8, pictureLength));
        if (picture != null) return picture;
      }
      pos = data.$2;
    }
    return null;
  }

  /// The content range of the first box called [type] among the boxes in
  /// [start, end), or null.
  Future<(int, int)?> _child(_Source file, int start, int end, String type) async {
    var pos = start;
    for (var i = 0; i < _maxEntries && pos + 8 <= end; i++) {
      final header = await file.read(pos, 16);
      if (header.length < 8) return null;
      var size = _be32(header, 0);
      var headerLength = 8;
      if (size == 1) {
        if (header.length < 16) return null;
        size = _be32(header, 8) * 0x100000000 + _be32(header, 12); // 64-bit size
        headerLength = 16;
      } else if (size == 0) {
        size = end - pos; // runs to the end
      }
      if (size < headerLength || pos + size > end) return null;
      if (_ascii(header, 4, 8) == type) return (pos + headerLength, pos + size);
      pos += size;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// [bytes] when they are a JPEG or PNG picture within the size cap.
  Uint8List? _image(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxPictureBytes) return null;
    return isJpegOrPng(bytes) ? Uint8List.fromList(bytes) : null;
  }

  /// Whether [bytes] start like a JPEG or a PNG file.
  static bool isJpegOrPng(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < png.length) return false;
    for (var i = 0; i < png.length; i++) {
      if (bytes[i] != png[i]) return false;
    }
    return true;
  }

  /// Undoes ID3 unsynchronisation: every `FF 00` becomes `FF`.
  static Uint8List _resync(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var from = 0;
    for (var i = 0; i + 1 < data.length; i++) {
      if (data[i] == 0xFF && data[i + 1] == 0x00) {
        out.add(Uint8List.sublistView(data, from, i + 1));
        from = i + 2;
        i++;
      }
    }
    if (from < data.length) out.add(Uint8List.sublistView(data, from));
    return out.takeBytes();
  }

  /// A 28-bit sync-safe number (7 bits per byte), or null when a byte has
  /// its top bit set.
  static int? _syncSafe(Uint8List b, int at) {
    if (b[at] | b[at + 1] | b[at + 2] | b[at + 3] >= 0x80) return null;
    return (b[at] << 21) | (b[at + 1] << 14) | (b[at + 2] << 7) | b[at + 3];
  }

  static int _be32(Uint8List b, int at) => (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static String _ascii(Uint8List b, int start, int end) => String.fromCharCodes(b.sublist(start, end));
}

/// Random access to bytes, from a file or from memory.
abstract class _Source {
  int get length;

  /// Up to [count] bytes at [offset] (fewer at the end).
  Future<Uint8List> read(int offset, int count);
}

class _FileSource implements _Source {
  final RandomAccessFile _file;
  @override
  final int length;

  _FileSource(this._file, this.length);

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || offset >= length || count <= 0) return Uint8List(0);
    await _file.setPosition(offset);
    return _file.read(count < length - offset ? count : length - offset);
  }
}

/// [_parent] seen from [_start], [length] bytes long.
class _OffsetSource implements _Source {
  final _Source _parent;
  final int _start;
  @override
  final int length;

  _OffsetSource(this._parent, this._start, this.length);

  @override
  Future<Uint8List> read(int offset, int count) {
    if (offset < 0 || offset >= length || count <= 0) return Future.value(Uint8List(0));
    return _parent.read(_start + offset, count < length - offset ? count : length - offset);
  }
}

class _MemorySource implements _Source {
  final Uint8List _bytes;

  _MemorySource(this._bytes);

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || offset >= _bytes.length || count <= 0) return Uint8List(0);
    final end = count < _bytes.length - offset ? offset + count : _bytes.length;
    return Uint8List.sublistView(_bytes, offset, end);
  }
}
