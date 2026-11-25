// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import 'dart:typed_data';

import 'media_sniffer.dart';

/// What a finished download really is: a song (sound only) or a video.
class MediaKindDecision {
  const MediaKindDecision({
    required this.isVideo,
    required this.mimeType,
    required this.byContent,
  });

  /// True when the file has a picture track: it belongs in Videos.
  final bool isVideo;

  /// The file's type, matching what it holds: `audio/mp4` for an MP4 with
  /// sound only, `video/mp4` for one with pictures.
  final String mimeType;

  /// True when the file itself decided (its tracks, or a format that only
  /// ever holds sound such as MP3). False when the file could not tell and
  /// the queued kind or the file name decided instead.
  final bool byContent;

  /// 'video' or 'audio', as the download rows store it.
  String get kind => isVideo ? 'video' : 'audio';

  @override
  String toString() => 'MediaKindDecision($kind, $mimeType, byContent: $byContent)';
}

/// Decides whether a downloaded file is a song or a video by looking inside
/// it, so it lands in the right library section (Music or Videos).
///
/// The first bytes alone cannot tell: an MP4 or WebM file may hold sound
/// only (YouTube's "audio only" M4A, a podcast, a direct .m4a link) or
/// pictures and sound. For those containers the file's track list is read:
/// - MP4 / M4A / MOV: each `moov/trak/mdia/hdlr` handler (`vide` or `soun`).
///   Only box headers and a few small boxes are read, never the media data,
///   so a 2 GB file costs a handful of tiny reads. A picture track that only
///   holds chapter images (an audiobook or podcast) does not count as video.
/// - WebM / MKV: each `Tracks/TrackEntry/TrackType` (1 video, 2 audio).
/// - Ogg: a Theora stream means video.
/// MP3, FLAC, WAV and AAC only ever hold sound; AVI is treated as video.
///
/// When the file cannot tell (a damaged or unusual file), the kind the
/// download was queued with decides, then the file name's extension, then
/// the first bytes.
///
/// Shared by the direct-link engine, the web link (yt-dlp) runner and the
/// one-time repair of downloads saved in the wrong section.
class MediaKindClassifier {
  MediaKindClassifier._();

  /// Extensions that name a sound-only file.
  static const Set<String> audioExtensions = {
    'mp3', 'm4a', 'm4b', 'm4p', 'f4a', 'aac', 'flac', 'wav', 'oga', 'ogg', 'opus', 'spx', 'weba', 'mka',
  };

  /// Extensions that name a video file.
  static const Set<String> videoExtensions = {
    'mp4', 'm4v', 'mov', 'qt', '3gp', '3g2', 'f4v', 'mkv', 'webm', 'ogv', 'avi',
  };

  /// Most boxes or elements looked at in one file (a damaged file can never
  /// keep the reader busy).
  static const int _maxNodes = 4096;

  /// Most bytes of an Ogg or AVI file searched for its stream types.
  static const int _scanBytes = 64 * 1024;

  /// The decision for [file], or null when it is not a media file at all
  /// (its first bytes match no known audio or video format).
  ///
  /// [kindHint] is the kind the download was queued with ('audio' when the
  /// user chose audio only, or the server said so); [fileName] is the name
  /// it is saved under. Both only decide when the file itself cannot.
  static MediaKindDecision? classifyFile(File file, {String? kindHint, String? fileName}) {
    RandomAccessFile? raf;
    try {
      raf = file.openSync(mode: FileMode.read);
      final length = raf.lengthSync();
      final head = _readAt(raf, 0, 64, length);
      final sniffed = MediaSniffer.sniff(head);
      if (sniffed == null) return null;
      return _decide(raf, length, head, sniffed, kindHint: kindHint, fileName: fileName);
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  static MediaKindDecision _decide(
    RandomAccessFile raf,
    int length,
    Uint8List head,
    String sniffed, {
    String? kindHint,
    String? fileName,
  }) {
    // Formats that only ever hold sound, or (AVI) are treated as video.
    switch (sniffed) {
      case 'audio/mpeg':
      case 'audio/flac':
      case 'audio/wav':
      case 'audio/aac':
        return MediaKindDecision(isVideo: false, mimeType: sniffed, byContent: true);
      case 'video/x-msvideo':
        return MediaKindDecision(isVideo: true, mimeType: sniffed, byContent: true);
    }

    if (sniffed == 'video/mp4' || sniffed == 'audio/mp4' || sniffed == 'video/quicktime') {
      final quickTime = sniffed == 'video/quicktime' || _ftypBrand(head) == 'qt  ';
      final tracks = _mp4Tracks(raf, length);
      final isVideo = tracks?.verdict ?? _fallbackIsVideo(sniffed, kindHint, fileName);
      return MediaKindDecision(
        isVideo: isVideo,
        mimeType: isVideo ? (quickTime ? 'video/quicktime' : 'video/mp4') : 'audio/mp4',
        byContent: tracks?.verdict != null,
      );
    }

    if (sniffed == 'video/webm') {
      final info = _matroskaTracks(raf, length);
      final isVideo = info.tracks?.verdict ?? _fallbackIsVideo(sniffed, kindHint, fileName);
      final matroska = info.docType == 'matroska';
      return MediaKindDecision(
        isVideo: isVideo,
        mimeType: matroska
            ? (isVideo ? 'video/x-matroska' : 'audio/x-matroska')
            : (isVideo ? 'video/webm' : 'audio/webm'),
        byContent: info.tracks?.verdict != null,
      );
    }

    if (sniffed == 'audio/ogg') {
      final tracks = _oggTracks(_readAt(raf, 0, _scanBytes, length));
      final isVideo = tracks?.verdict ?? _fallbackIsVideo(sniffed, kindHint, fileName);
      return MediaKindDecision(
        isVideo: isVideo,
        mimeType: isVideo ? 'video/ogg' : 'audio/ogg',
        byContent: tracks?.verdict != null,
      );
    }

    // Anything the sniffer may learn later: its own word.
    final isVideo = _fallbackIsVideo(sniffed, kindHint, fileName);
    return MediaKindDecision(isVideo: isVideo, mimeType: sniffed, byContent: false);
  }

  /// When the file cannot tell: the queued kind, then the extension, then
  /// the first bytes.
  static bool _fallbackIsVideo(String sniffed, String? kindHint, String? fileName) {
    if (kindHint == 'audio') return false;
    if (kindHint == 'video') return true;
    final ext = extensionOf(fileName);
    if (audioExtensions.contains(ext)) return false;
    if (videoExtensions.contains(ext)) return true;
    return sniffed.startsWith('video/');
  }

  /// The lower-case extension of [name] without its dot, or '' when it has
  /// none.
  static String extensionOf(String? name) {
    if (name == null) return '';
    final base = name.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  // ------------------------------------------------------------ reading

  static Uint8List _readAt(RandomAccessFile raf, int position, int count, int length) {
    if (position < 0 || position >= length || count <= 0) return Uint8List(0);
    final n = (position + count > length) ? length - position : count;
    raf.setPositionSync(position);
    return raf.readSync(n);
  }

  static int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static String _fourCc(Uint8List b, int o) => String.fromCharCodes(b.sublist(o, o + 4));

  static String? _ftypBrand(Uint8List head) {
    if (head.length < 12 || _fourCc(head, 4) != 'ftyp') return null;
    return _fourCc(head, 8);
  }

  // ------------------------------------------------------------ MP4 / MOV

  /// One box: its type and where its contents start and end.
  static _Box? _boxAt(RandomAccessFile raf, int pos, int parentEnd) {
    if (pos + 8 > parentEnd) return null;
    final h = _readAt(raf, pos, 16, parentEnd);
    if (h.length < 8) return null;
    var size = _u32(h, 0);
    final type = _fourCc(h, 4);
    var header = 8;
    if (size == 1) {
      if (h.length < 16) return null;
      // A 64-bit size (large media data). Anything beyond 2^53 is damage.
      final hi = _u32(h, 8);
      final lo = _u32(h, 12);
      if (hi > 0x1FFFFF) return null;
      size = hi * 0x100000000 + lo;
      header = 16;
    } else if (size == 0) {
      size = parentEnd - pos; // runs to the end of its parent
    }
    if (size < header) return null;
    final end = pos + size > parentEnd ? parentEnd : pos + size;
    return _Box(type, pos + header, end);
  }

  /// The children of the box running from [start] to [end].
  static Iterable<_Box> _children(RandomAccessFile raf, int start, int end, _Budget budget) sync* {
    var pos = start;
    while (pos + 8 <= end && budget.take()) {
      final box = _boxAt(raf, pos, end);
      if (box == null) return;
      yield box;
      if (box.end <= pos) return;
      pos = box.end;
    }
  }

  static _Tracks? _mp4Tracks(RandomAccessFile raf, int length) {
    try {
      final budget = _Budget(_maxNodes);
      for (final top in _children(raf, 0, length, budget)) {
        if (top.type != 'moov') continue;
        final tracks = <_Mp4Track>[];
        for (final child in _children(raf, top.start, top.end, budget)) {
          if (child.type == 'trak') tracks.add(_mp4Track(raf, child, budget));
        }
        // Picture tracks that only hold chapter images (referenced by
        // another track's `tref/chap`) are not video.
        final chapterIds = {for (final t in tracks) ...t.chapterRefs};
        var video = false;
        var audio = false;
        for (final t in tracks) {
          if (t.handler == 'vide' && !(t.id != null && chapterIds.contains(t.id))) video = true;
          if (t.handler == 'soun') audio = true;
        }
        return _Tracks(video: video, audio: audio);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static _Mp4Track _mp4Track(RandomAccessFile raf, _Box trak, _Budget budget) {
    final track = _Mp4Track();
    for (final box in _children(raf, trak.start, trak.end, budget)) {
      switch (box.type) {
        case 'tkhd':
          // version(1) flags(3), then the times (4 or 8 bytes each), then the id.
          final b = _readAt(raf, box.start, 24, box.end);
          if (b.isEmpty) break;
          final idAt = b[0] == 1 ? 20 : 12;
          if (b.length >= idAt + 4) track.id = _u32(b, idAt);
        case 'tref':
          for (final ref in _children(raf, box.start, box.end, budget)) {
            if (ref.type != 'chap') continue;
            final count = ((ref.end - ref.start) ~/ 4).clamp(0, 64);
            final b = _readAt(raf, ref.start, count * 4, ref.end);
            for (var i = 0; i + 4 <= b.length; i += 4) {
              track.chapterRefs.add(_u32(b, i));
            }
          }
        case 'mdia':
          for (final m in _children(raf, box.start, box.end, budget)) {
            if (m.type != 'hdlr') continue;
            // version/flags(4), pre_defined(4), handler_type(4).
            final b = _readAt(raf, m.start, 12, m.end);
            if (b.length >= 12) track.handler = _fourCc(b, 8);
          }
      }
    }
    return track;
  }

  // ------------------------------------------------------------ WebM / MKV

  static const int _idEbml = 0x1A45DFA3;
  static const int _idDocType = 0x4282;
  static const int _idSegment = 0x18538067;
  static const int _idTracks = 0x1654AE6B;
  static const int _idTrackEntry = 0xAE;
  static const int _idTrackType = 0x83;
  static const int _idCluster = 0x1F43B675;

  static _MatroskaInfo _matroskaTracks(RandomAccessFile raf, int length) {
    String? docType;
    try {
      final budget = _Budget(_maxNodes);
      var pos = 0;
      while (pos < length && budget.take()) {
        final el = _ebmlAt(raf, pos, length);
        if (el == null) break;
        if (el.id == _idEbml) {
          docType = _ebmlDocType(raf, el, budget);
        } else if (el.id == _idSegment) {
          return _MatroskaInfo(docType, _segmentTracks(raf, el, budget));
        }
        if (el.unknownSize) break;
        pos = el.end;
      }
    } catch (_) {}
    return _MatroskaInfo(docType, null);
  }

  static String? _ebmlDocType(RandomAccessFile raf, _Element header, _Budget budget) {
    var pos = header.start;
    while (pos < header.end && budget.take()) {
      final el = _ebmlAt(raf, pos, header.end);
      if (el == null || el.unknownSize) return null;
      if (el.id == _idDocType) {
        final b = _readAt(raf, el.start, (el.end - el.start).clamp(0, 32), el.end);
        return String.fromCharCodes(b.where((c) => c != 0)).toLowerCase();
      }
      pos = el.end;
    }
    return null;
  }

  static _Tracks? _segmentTracks(RandomAccessFile raf, _Element segment, _Budget budget) {
    var pos = segment.start;
    while (pos < segment.end && budget.take()) {
      final el = _ebmlAt(raf, pos, segment.end);
      if (el == null) return null;
      if (el.id == _idTracks) {
        var video = false;
        var audio = false;
        var entryPos = el.start;
        while (entryPos < el.end && budget.take()) {
          final entry = _ebmlAt(raf, entryPos, el.end);
          if (entry == null || entry.unknownSize) break;
          if (entry.id == _idTrackEntry) {
            final type = _trackType(raf, entry, budget);
            if (type == 1) video = true;
            if (type == 2) audio = true;
          }
          entryPos = entry.end;
        }
        return _Tracks(video: video, audio: audio);
      }
      // Media data before any track list: the file does not say.
      if (el.id == _idCluster || el.unknownSize) return null;
      pos = el.end;
    }
    return null;
  }

  static int? _trackType(RandomAccessFile raf, _Element entry, _Budget budget) {
    var pos = entry.start;
    while (pos < entry.end && budget.take()) {
      final el = _ebmlAt(raf, pos, entry.end);
      if (el == null || el.unknownSize) return null;
      if (el.id == _idTrackType) {
        final b = _readAt(raf, el.start, (el.end - el.start).clamp(0, 8), el.end);
        var v = 0;
        for (final x in b) {
          v = (v << 8) | x;
        }
        return v;
      }
      pos = el.end;
    }
    return null;
  }

  /// One EBML element: its id and where its contents start and end.
  static _Element? _ebmlAt(RandomAccessFile raf, int pos, int parentEnd) {
    final b = _readAt(raf, pos, 12, parentEnd);
    if (b.isEmpty) return null;
    final idLen = _vintLength(b[0]);
    if (idLen == 0 || idLen > 4 || b.length < idLen + 1) return null;
    var id = 0;
    for (var i = 0; i < idLen; i++) {
      id = (id << 8) | b[i];
    }
    final sizeLen = _vintLength(b[idLen]);
    if (sizeLen == 0 || b.length < idLen + sizeLen) return null;
    var size = b[idLen] & (0xFF >> sizeLen);
    var allOnes = size == (0xFF >> sizeLen);
    for (var i = 1; i < sizeLen; i++) {
      final x = b[idLen + i];
      if (x != 0xFF) allOnes = false;
      size = size * 256 + x;
    }
    final start = pos + idLen + sizeLen;
    if (allOnes) return _Element(id, start, parentEnd, unknownSize: true);
    final end = start + size > parentEnd ? parentEnd : start + size;
    return _Element(id, start, end);
  }

  /// Bytes in an EBML variable-length number starting with [first]; 0 when
  /// it is not one.
  static int _vintLength(int first) {
    for (var i = 0; i < 8; i++) {
      if (first & (0x80 >> i) != 0) return i + 1;
    }
    return 0;
  }

  // ------------------------------------------------------------ Ogg

  static _Tracks? _oggTracks(Uint8List bytes) {
    bool has(List<int> pattern) => _indexOf(bytes, pattern) >= 0;
    final video = has(const [0x80, 0x74, 0x68, 0x65, 0x6F, 0x72, 0x61]); // \x80theora
    final audio = has('OpusHead'.codeUnits) ||
        has(const [0x01, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]) || // \x01vorbis
        has(const [0x7F, 0x46, 0x4C, 0x41, 0x43]) || // \x7FFLAC
        has('Speex   '.codeUnits);
    if (!video && !audio) return null;
    return _Tracks(video: video, audio: audio);
  }

  static int _indexOf(Uint8List bytes, List<int> pattern) {
    outer:
    for (var i = 0; i + pattern.length <= bytes.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  // ------------------------------------------------------------ names

  /// Extensions download servers put on files that are not a media name:
  /// replaced by the real one when the file is saved.
  static const Set<String> _placeholderExtensions = {
    'bin', 'dat', 'raw', 'file', 'download', 'dl', 'octet-stream', 'php', 'asp', 'aspx', 'jsp', 'cgi', 'html', 'htm',
  };

  /// [safeName] (already sanitized) saved with a media extension, so every
  /// player (iPhone's in particular, which goes by the extension) knows what
  /// it is: a name without one gets [mediaExtension] added ("track" ->
  /// "track.mp3"), a placeholder such as `.bin` or `.php` is replaced
  /// ("get.bin" -> "get.mp3"), and a name that already ends in an audio or
  /// video extension is kept as it is.
  static String nameWithMediaExtension(String safeName, String mediaExtension) {
    var ext = mediaExtension.trim().toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext.isEmpty || ext == 'bin') return safeName;
    final current = extensionOf(safeName);
    if (audioExtensions.contains(current) || videoExtensions.contains(current)) return safeName;
    if (current.isNotEmpty && _placeholderExtensions.contains(current)) {
      final base = safeName.substring(0, safeName.length - current.length - 1);
      if (base.trim().isEmpty) return 'download.$ext';
      return '$base.$ext';
    }
    return '$safeName.$ext';
  }
}

class _Box {
  _Box(this.type, this.start, this.end);
  final String type;
  final int start;
  final int end;
}

class _Element {
  _Element(this.id, this.start, this.end, {this.unknownSize = false});
  final int id;
  final int start;
  final int end;
  final bool unknownSize;
}

class _Mp4Track {
  int? id;
  String? handler;
  final Set<int> chapterRefs = {};
}

class _Tracks {
  const _Tracks({required this.video, required this.audio});
  final bool video;
  final bool audio;

  /// True: video. False: sound only. Null: neither kind of track was found.
  bool? get verdict => video ? true : (audio ? false : null);
}

class _MatroskaInfo {
  const _MatroskaInfo(this.docType, this.tracks);
  final String? docType;
  final _Tracks? tracks;
}

class _Budget {
  _Budget(this._left);
  int _left;
  bool take() => _left-- > 0;
}
