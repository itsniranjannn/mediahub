// The pure-Dart cover reader for the iPhone (iOS parity P3, task 2): the
// cover embedded in a downloaded MP3 (ID3v2.3 / v2.4 APIC, unsynchronised
// too), M4A (the iTunes covr atom) or FLAC (the PICTURE block). Every file
// is built byte by byte here; only JPEG and PNG come back, within the size
// cap.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/services/embedded_cover_reader.dart';

/// A "JPEG": the reader only checks the start. Holds FF bytes followed by
/// E0+ and 00, which ID3 unsynchronisation has to escape.
final Uint8List _jpeg = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0xFF, 0x00, 0x12, 0xFF, 0xFF, 0xE1, 0x34, 0x56, 0xFF, 0xD9,
]);

final Uint8List _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 1, 2, 3, 4, //
]);

/// A PNG over 127 bytes, so its ID3v2.4 frame size needs two sync-safe bytes.
final Uint8List _bigPng = Uint8List.fromList([..._png, for (var i = 0; i < 300; i++) i & 0xFF]);

final Uint8List _gif = Uint8List.fromList(ascii.encode('GIF89a') + [1, 2, 3, 4, 5]);

/// MPEG audio frames after the tag (FF FB is a frame sync).
final Uint8List _audio = Uint8List.fromList([for (var i = 0; i < 64; i++) i.isEven ? 0xFF : 0xFB]);

List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _be24(int v) => [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _syncSafe(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

/// ID3 unsynchronisation: a 00 after every FF (more than the minimum, which
/// a reader must still undo).
List<int> _unsync(List<int> bytes) => [
      for (final b in bytes) ...[b, if (b == 0xFF) 0x00],
    ];

/// APIC frame data: encoding, MIME, picture type, description, picture.
List<int> _apicData(Uint8List picture, {int type = 3, String mime = 'image/jpeg', int encoding = 0, String desc = 'cover'}) {
  final description = switch (encoding) {
    1 => [0xFF, 0xFE, for (final c in desc.codeUnits) ...[c & 0xFF, c >> 8], 0, 0],
    2 => [for (final c in desc.codeUnits) ...[c >> 8, c & 0xFF], 0, 0],
    _ => [...utf8.encode(desc), 0],
  };
  return [encoding, ...ascii.encode(mime), 0, type, ...description, ...picture];
}

List<int> _frame(String id, List<int> data, {required int major, int formatFlags = 0}) => [
      ...ascii.encode(id),
      ...(major == 4 ? _syncSafe(data.length) : _be32(data.length)),
      0,
      formatFlags,
      ...data,
    ];

List<int> _textFrame(String id, String text, {required int major}) =>
    _frame(id, [3, ...utf8.encode(text)], major: major);

/// An ID3v2 tag around [frames] (already encoded), with 32 bytes of padding.
List<int> _id3(List<int> frames, {required int major, int flags = 0}) {
  final body = [...frames, ...List.filled(32, 0)];
  return [...ascii.encode('ID3'), major, 0, flags, ..._syncSafe(body.length), ...body];
}

List<int> _box(String type, List<int> content) => [..._be32(content.length + 8), ...latin1.encode(type), ...content];

/// An M4A with [cover] in moov/udta/meta/ilst/covr/data (type 13 JPEG, 14 PNG).
List<int> _m4a(Uint8List? cover, {int coverType = 13, bool moovFirst = true, bool fullBoxMeta = true}) {
  final ftyp = _box('ftyp', [...ascii.encode('M4A '), 0, 0, 0, 0, ...ascii.encode('M4A isom')]);
  final mdat = _box('mdat', List.filled(4096, 0xAB));
  final hdlr = _box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...ascii.encode('mdir'), ...List.filled(12, 0), 0]);
  final title = _box('©nam', _box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode('Song')]));
  final ilst = _box('ilst', [
    ...title,
    if (cover != null) ..._box('covr', _box('data', [0, 0, 0, coverType, 0, 0, 0, 0, ...cover])),
  ]);
  final meta = _box('meta', [if (fullBoxMeta) ...[0, 0, 0, 0], ...hdlr, ...ilst]);
  final moov = _box('moov', [
    ..._box('mvhd', List.filled(100, 0)),
    ..._box('trak', List.filled(200, 0)),
    ..._box('udta', meta),
  ]);
  return moovFirst ? [...ftyp, ...moov, ...mdat] : [...ftyp, ...mdat, ...moov];
}

/// A FLAC metadata block.
List<int> _flacBlock(int type, List<int> data, {bool last = false}) => [(last ? 0x80 : 0) | type, ..._be24(data.length), ...data];

List<int> _flacPicture(Uint8List picture, {int type = 3, String mime = 'image/jpeg'}) => [
      ..._be32(type),
      ..._be32(mime.length),
      ...ascii.encode(mime),
      ..._be32(5),
      ...utf8.encode('cover'),
      ..._be32(500), ..._be32(500), ..._be32(24), ..._be32(0), // width, height, depth, colours
      ..._be32(picture.length),
      ...picture,
    ];

List<int> _flac(List<List<int>> pictures) => [
      ...ascii.encode('fLaC'),
      ..._flacBlock(0, List.filled(34, 0x11), last: pictures.isEmpty), // STREAMINFO
      for (var i = 0; i < pictures.length; i++) ..._flacBlock(6, pictures[i], last: i == pictures.length - 1),
      ..._audio,
    ];

void main() {
  late Directory dir;
  const reader = EmbeddedCoverReader();
  var n = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cover_reader_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<String> write(List<int> bytes, [String ext = 'mp3']) async {
    final file = File('${dir.path}${Platform.pathSeparator}file${n++}.$ext');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  group('MP3 (ID3v2 APIC)', () {
    test('ID3v2.3: the front cover, past the text frames', () async {
      final path = await write([
        ..._id3([
          ..._textFrame('TIT2', 'Resham Firiri', major: 3),
          ..._frame('APIC', _apicData(_jpeg), major: 3),
        ], major: 3),
        ..._audio,
      ]);
      expect(await reader.read(path), _jpeg);
    });

    test('ID3v2.4 with sync-safe sizes, a UTF-16 description and a PNG', () async {
      final path = await write([
        ..._id3([
          ..._textFrame('TIT2', 'गीत', major: 4),
          ..._frame('APIC', _apicData(_bigPng, mime: 'image/png', encoding: 1, desc: 'front'), major: 4),
        ], major: 4),
        ..._audio,
      ]);
      expect(await reader.read(path), _bigPng);
    });

    test('UTF-16BE description (encoding 2)', () async {
      final path = await write([
        ..._id3([..._frame('APIC', _apicData(_jpeg, encoding: 2, desc: 'ab'), major: 4)], major: 4),
        ..._audio,
      ]);
      expect(await reader.read(path), _jpeg);
    });

    test('the front cover wins over another picture; any picture beats none', () async {
      final both = await write([
        ..._id3([
          ..._frame('APIC', _apicData(_png, type: 4, mime: 'image/png'), major: 3), // back cover
          ..._frame('APIC', _apicData(_jpeg, type: 3), major: 3), // front cover
        ], major: 3),
        ..._audio,
      ]);
      expect(await reader.read(both), _jpeg);

      final backOnly = await write([
        ..._id3([..._frame('APIC', _apicData(_png, type: 4, mime: 'image/png'), major: 3)], major: 3),
        ..._audio,
      ]);
      expect(await reader.read(backOnly), _png);
    });

    test('ID3v2.3 with the whole tag unsynchronised', () async {
      final frames = [
        ..._textFrame('TIT2', 'x', major: 3),
        ..._frame('APIC', _apicData(_jpeg), major: 3),
        ...List.filled(32, 0),
      ];
      final body = _unsync(frames);
      final path = await write([...ascii.encode('ID3'), 3, 0, 0x80, ..._syncSafe(body.length), ...body, ..._audio]);
      expect(await reader.read(path), _jpeg);
    });

    test('ID3v2.4 with an unsynchronised frame and a data length indicator', () async {
      final data = _apicData(_jpeg);
      final encoded = [..._syncSafe(data.length), ..._unsync(data)];
      final path = await write([
        ..._id3([..._frame('APIC', encoded, major: 4, formatFlags: 0x02 | 0x01)], major: 4),
        ..._audio,
      ]);
      expect(await reader.read(path), _jpeg);
    });

    test('ID3v2.4 written with plain frame sizes (old iTunes)', () async {
      // 300 is 00 00 01 2C: every byte under 0x80, so it also reads as a
      // (wrong) sync-safe 172, which lands inside the title.
      final title = [3, ...List.filled(299, 0x61)];
      final path = await write([
        ..._id3([
          ..._frame('TIT2', title, major: 3), // v2.3 frames have plain sizes
          ..._frame('APIC', _apicData(_bigPng, mime: 'image/png'), major: 3),
        ], major: 4),
        ..._audio,
      ]);
      expect(await reader.read(path), _bigPng);
    });

    test('ID3v2.3 with an extended header', () async {
      final frames = [..._frame('APIC', _apicData(_jpeg), major: 3), ...List.filled(16, 0)];
      final ext = [..._be32(6), 0, 0, 0, 0, 0, 0]; // size 6 (without itself), flags, padding size
      final body = [...ext, ...frames];
      final path = await write([...ascii.encode('ID3'), 3, 0, 0x40, ..._syncSafe(body.length), ...body, ..._audio]);
      expect(await reader.read(path), _jpeg);
    });

    test('no picture, a GIF, a link or a compressed frame: nothing', () async {
      final noPicture = await write([..._id3([..._textFrame('TIT2', 'x', major: 3)], major: 3), ..._audio]);
      expect(await reader.read(noPicture), isNull);

      final gif = await write([
        ..._id3([..._frame('APIC', _apicData(_gif, mime: 'image/gif'), major: 3)], major: 3),
        ..._audio,
      ]);
      expect(await reader.read(gif), isNull, reason: 'JPEG and PNG only');

      final link = await write([
        ..._id3([..._frame('APIC', _apicData(Uint8List.fromList(ascii.encode('http://x/y.jpg')), mime: '-->'), major: 3)],
            major: 3),
        ..._audio,
      ]);
      expect(await reader.read(link), isNull);

      final compressed = await write([
        ..._id3([..._frame('APIC', _apicData(_jpeg), major: 4, formatFlags: 0x08 | 0x01)], major: 4),
        ..._audio,
      ]);
      expect(await reader.read(compressed), isNull);
    });

    test('ID3v2.2 is not read (it has no APIC frame)', () async {
      final path = await write([...ascii.encode('ID3'), 2, 0, 0, ..._syncSafe(20), ...List.filled(20, 0), ..._audio]);
      expect(await reader.read(path), isNull);
    });
  });

  group('M4A (covr atom)', () {
    test('moov/udta/meta/ilst/covr/data, JPEG and PNG', () async {
      expect(await reader.read(await write(_m4a(_jpeg), 'm4a')), _jpeg);
      expect(await reader.read(await write(_m4a(_png, coverType: 14), 'm4a')), _png);
    });

    test('moov after the audio data is found by seeking past it', () async {
      expect(await reader.read(await write(_m4a(_jpeg, moovFirst: false), 'm4a')), _jpeg);
    });

    test('a QuickTime-style meta box (no version and flags)', () async {
      expect(await reader.read(await write(_m4a(_jpeg, fullBoxMeta: false), 'm4a')), _jpeg);
    });

    test('no covr (a YouTube download) or a BMP cover: nothing', () async {
      expect(await reader.read(await write(_m4a(null), 'm4a')), isNull);
      final bmp = Uint8List.fromList([0x42, 0x4D, 1, 2, 3, 4, 5, 6]);
      expect(await reader.read(await write(_m4a(bmp, coverType: 27), 'm4a')), isNull);
    });
  });

  group('FLAC (PICTURE block)', () {
    test('the front cover after STREAMINFO', () async {
      expect(await reader.read(await write(_flac([_flacPicture(_jpeg)]), 'flac')), _jpeg);
    });

    test('the front cover wins over another picture', () async {
      final path = await write(_flac([_flacPicture(_png, type: 0, mime: 'image/png'), _flacPicture(_jpeg)]), 'flac');
      expect(await reader.read(path), _jpeg);
    });

    test('a FLAC file with an ID3 tag in front of it', () async {
      final path = await write([..._id3([..._textFrame('TIT2', 'x', major: 3)], major: 3), ..._flac([_flacPicture(_png)])], 'flac');
      expect(await reader.read(path), _png);
    });

    test('no PICTURE block: nothing', () async {
      expect(await reader.read(await write(_flac([]), 'flac')), isNull);
    });
  });

  group('limits and bad files', () {
    test('a picture over the size cap is skipped', () async {
      const small = EmbeddedCoverReader(maxPictureBytes: 16);
      final mp3 = await write([..._id3([..._frame('APIC', _apicData(_jpeg), major: 3)], major: 3), ..._audio]);
      expect(await small.read(mp3), isNull);
      expect(await small.read(await write(_m4a(_jpeg), 'm4a')), isNull);
      expect(await small.read(await write(_flac([_flacPicture(_jpeg)]), 'flac')), isNull);
      expect(await reader.read(mp3), _jpeg, reason: 'the default cap allows it');
    });

    test('empty, too short, unknown, truncated or missing files give null, never an error', () async {
      expect(await reader.read(await write([])), isNull);
      expect(await reader.read(await write([0x49, 0x44, 0x33])), isNull);
      expect(await reader.read(await write(List.filled(100, 0x55))), isNull);
      final whole = [..._id3([..._frame('APIC', _apicData(_jpeg), major: 3)], major: 3), ..._audio];
      expect(await reader.read(await write(whole.sublist(0, 30))), isNull, reason: 'cut in the middle of the frame');
      final m4a = _m4a(_jpeg);
      expect(await reader.read(await write(m4a.sublist(0, m4a.length - 4200), 'm4a')), isNull);
      // A box shorter than its own header would loop forever if trusted.
      expect(await reader.read(await write([..._be32(20), ...ascii.encode('ftyp'), ...List.filled(12, 0), 0, 0, 0, 4, ...ascii.encode('free')], 'm4a')),
          isNull);
      expect(await reader.read('${dir.path}${Platform.pathSeparator}missing.mp3'), isNull);
    });

    test('the file is closed afterwards (it can be deleted at once)', () async {
      final path = await write(_m4a(_jpeg), 'm4a');
      expect(await reader.read(path), _jpeg);
      await File(path).delete();
      expect(File(path).existsSync(), isFalse);
    });
  });
}
