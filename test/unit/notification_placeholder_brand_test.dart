import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';

/// The media notification / lock screen cover for songs without one is the
/// branded Sindur placeholder: dark wine -> plum field, crimson/amber glyph.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ByteData> pixels(String seed) async {
    final png = await renderPlaceholderPng(seed, size: 64);
    expect(png, isNotNull);
    final codec = await ui.instantiateImageCodec(png!);
    final frame = await codec.getNextFrame();
    return (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  }

  Color at(ByteData d, int x, int y) {
    final i = (y * 64 + x) * 4;
    return Color.fromARGB(d.getUint8(i + 3), d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2));
  }

  test('a dark wine/plum field: opaque, dark, red-leaning corners', () async {
    final d = await pixels('song-a');
    for (final c in [at(d, 1, 1), at(d, 62, 62)]) {
      expect(c.a, 1.0);
      expect(c.computeLuminance(), lessThan(0.05), reason: 'dark field');
      expect(c.r, greaterThan(c.g), reason: 'wine / plum, not grey');
    }
  });

  test('the same branded cover for every song', () async {
    final a = await pixels('song-a');
    final b = await pixels('another-song');
    expect(a.buffer.asUint8List(), b.buffer.asUint8List());
  });

  test('the gradients are the Sindur wine, plum, crimson and amber', () {
    expect(brandPlaceholderGradient.colors.first, const Color(0xFF4A0A1A));
    expect(brandPlaceholderGradient.colors.last, const Color(0xFF2A0F26));
    expect(brandPlaceholderGlyph.colors, const [Color(0xFFCC324C), Color(0xFFE89A2C)]);
  });
}
