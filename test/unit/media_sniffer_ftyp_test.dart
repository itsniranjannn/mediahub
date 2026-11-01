import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/media_sniffer.dart';

void main() {
  group('TASK 5.2d Item 4: MediaSniffer ftyp Major Brand Sniffing', () {
    List<int> makeFtyp(String brand) {
      final bytes = Uint8List(12);
      // bytes 0..3: box length
      bytes[0] = 0; bytes[1] = 0; bytes[2] = 0; bytes[3] = 20;
      // bytes 4..7: 'ftyp'
      bytes[4] = 0x66; bytes[5] = 0x74; bytes[6] = 0x79; bytes[7] = 0x70;
      // bytes 8..11: brand ASCII
      for (int i = 0; i < 4 && i < brand.length; i++) {
        bytes[8 + i] = brand.codeUnitAt(i);
      }
      return bytes;
    }

    test('M4A, M4B, F4A major brands are recognized as audio/mp4', () {
      expect(MediaSniffer.sniff(makeFtyp('M4A ')), equals('audio/mp4'));
      expect(MediaSniffer.sniff(makeFtyp('M4B ')), equals('audio/mp4'));
      expect(MediaSniffer.sniff(makeFtyp('F4A ')), equals('audio/mp4'));
      expect(MediaSniffer.sniff(makeFtyp('M4P ')), equals('audio/mp4'));
    });

    test('Other major brands (isom, mp42, avc1) are recognized as video/mp4', () {
      expect(MediaSniffer.sniff(makeFtyp('isom')), equals('video/mp4'));
      expect(MediaSniffer.sniff(makeFtyp('mp42')), equals('video/mp4'));
      expect(MediaSniffer.sniff(makeFtyp('avc1')), equals('video/mp4'));
      expect(MediaSniffer.sniff(makeFtyp('dash')), equals('video/mp4'));
    });
  });
}

