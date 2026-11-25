// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';

void main() {
  test('kind is guessed from the file extension while downloading', () {
    expect(kindFromName('Big Buck Bunny.mp4'), 'video');
    expect(kindFromName('clip.WEBM'), 'video');
    expect(kindFromName('song.mp3'), 'audio');
    expect(kindFromName('/sdcard/x/track.m4a'), 'audio');
    expect(kindFromName('noext'), isNull);
    expect(kindFromName('file.bin'), isNull);
    expect(kindFromName('trailing.'), isNull);
  });
}
