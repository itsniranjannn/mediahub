import 'dart:typed_data';

class MediaSniffer {
  MediaSniffer._();

  /// Boxes a QuickTime file without 'ftyp' may start with, or have next.
  static const Set<String> _quickTimeTopBoxes = {'moov', 'mdat', 'wide', 'free', 'skip', 'pnot'};

  /// The first box inside a QuickTime 'moov': the movie header (or its
  /// compressed or profile form).
  static const Set<String> _moovFirstChildren = {'mvhd', 'cmov', 'prfl'};

  /// True when [u8] starts the way a QuickTime file without 'ftyp' does, with
  /// more than four letters to show for it (so a file that merely has
  /// "free" or "skip" at bytes 4-7 is not taken for a video):
  /// - 'moov' whose first child is the movie header;
  /// - 'mdat' (the media data first, the track list at the end);
  /// - a filler ('wide', 'free', 'skip') or preview ('pnot') box followed,
  ///   within the bytes read, by another QuickTime box (or the preview picture).
  static bool _looksLikeQuickTime(Uint8List u8) {
    if (u8.length < 16) return false;
    int sizeAt(int at) => (u8[at] << 24) | (u8[at + 1] << 16) | (u8[at + 2] << 8) | u8[at + 3];
    String typeAt(int at) => String.fromCharCodes(u8.sublist(at + 4, at + 8));
    final size = sizeAt(0);
    final type = typeAt(0);
    if (!_quickTimeTopBoxes.contains(type)) return false;
    if (type == 'mdat') return size >= 8 || size == 1;
    if (type == 'moov') return size >= 16 && _moovFirstChildren.contains(typeAt(8));
    if (size < 8 || size + 8 > u8.length) return false;
    final next = typeAt(size);
    return _quickTimeTopBoxes.contains(next) || (type == 'pnot' && next == 'PICT');
  }

  /// Sniffs the magic bytes of a media file header.
  /// Supported:
  /// - MP3: ID3 tag ('ID3') or frame sync (0xFF 0xFB, 0xFF 0xF3, 0xFF 0xF2, 0xFF 0xE0..0xFF 0xFF)
  /// - MP4 / M4A: 'ftyp' at offset 4
  /// - QuickTime MOV without 'ftyp': 'moov', 'mdat', 'wide', 'free', 'skip' or 'pnot' at offset 4
  /// - WAV: RIFF at offset 0 and WAVE at offset 8
  /// - AVI: RIFF at offset 0 and 'AVI ' at offset 8
  /// - FLAC: 'fLaC' at offset 0
  /// - OGG: 'OggS' at offset 0
  /// - WebM / MKV: 0x1A 0x45 0xDF 0xA3 at offset 0
  /// - AAC ADTS: 0xFF 0xF1 or 0xFF 0xF9
  ///
  /// Returns the detected mimeType or media type string, or null if not a recognized media file.
  static String? sniff(List<int> bytes) {
    if (bytes.length < 4) return null;

    final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    // 1. MP3 ID3 header: 'ID3' (49 44 33)
    if (u8[0] == 0x49 && u8[1] == 0x44 && u8[2] == 0x33) {
      return 'audio/mpeg';
    }

    // 2. FLAC: 'fLaC' (66 4C 61 43)
    if (u8[0] == 0x66 && u8[1] == 0x4C && u8[2] == 0x61 && u8[3] == 0x43) {
      return 'audio/flac';
    }

    // 3. OGG: 'OggS' (4F 67 67 53)
    if (u8[0] == 0x4F && u8[1] == 0x67 && u8[2] == 0x67 && u8[3] == 0x53) {
      return 'audio/ogg';
    }

    // 4. WebM / MKV: 1A 45 DF A3
    if (u8[0] == 0x1A && u8[1] == 0x45 && u8[2] == 0xDF && u8[3] == 0xA3) {
      return 'video/webm';
    }

    // 5. MP4 / M4A: 'ftyp' at offset 4
    if (u8.length >= 8 &&
        u8[4] == 0x66 && // f
        u8[5] == 0x74 && // t
        u8[6] == 0x79 && // y
        u8[7] == 0x70) { // p
      // For ftyp, read major brand at bytes 8-11
      if (u8.length >= 12) {
        final brand = String.fromCharCodes(u8.sublist(8, 12)).trim().toUpperCase();
        // M4A, M4B, F4A are audio/mp4; everything else is video/mp4
        if (brand == 'M4A' || brand == 'M4B' || brand == 'F4A' || brand == 'M4P') {
          return 'audio/mp4';
        }
      }
      return 'video/mp4';
    }

    // 5b. QuickTime MOV without an 'ftyp' box (older cameras and editors):
    // the file starts straight with one of QuickTime's own top-level boxes.
    if (_looksLikeQuickTime(u8)) return 'video/quicktime';

    // 6. WAV: 'RIFF' at offset 0 and 'WAVE' at offset 8
    if (u8.length >= 12 &&
        u8[0] == 0x52 && u8[1] == 0x49 && u8[2] == 0x46 && u8[3] == 0x46 && // RIFF
        u8[8] == 0x57 && u8[9] == 0x41 && u8[10] == 0x56 && u8[11] == 0x45) { // WAVE
      return 'audio/wav';
    }

    // 6b. AVI: 'RIFF' at offset 0 and 'AVI ' at offset 8
    if (u8.length >= 12 &&
        u8[0] == 0x52 && u8[1] == 0x49 && u8[2] == 0x46 && u8[3] == 0x46 && // RIFF
        u8[8] == 0x41 && u8[9] == 0x56 && u8[10] == 0x49 && u8[11] == 0x20) { // 'AVI '
      return 'video/x-msvideo';
    }

    // 7. MP3 Frame sync: 11 bits set (0xFF followed by 0xE0..0xFF)
    if (u8[0] == 0xFF && (u8[1] & 0xE0) == 0xE0) {
      // Could be MP3 frame sync or AAC ADTS
      final layer = (u8[1] >> 1) & 0x03;
      if (layer != 0) {
        return 'audio/mpeg';
      } else {
        return 'audio/aac';
      }
    }

    return null;
  }
}

