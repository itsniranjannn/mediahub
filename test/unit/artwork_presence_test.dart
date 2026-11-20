import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/services/artwork_presence.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/domain/models/media_item.dart';

MediaItem _song(String uri, {String? artworkPath}) => MediaItem(
      id: uri,
      uri: uri,
      mediaType: MediaType.audio,
      title: 'Song',
      durationMs: 1000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      artworkPath: artworkPath,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mediahub/media_store');
  const withArt = 'content://media/external/audio/media/1';
  const withoutArt = 'content://media/external/audio/media/2';
  const withAtSign = 'file:///music/live@256.mp3';

  setUp(() {
    ArtworkService.instance.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        final uri = (call.arguments as Map)['uri'];
        return uri == withArt || uri == withAtSign ? <int>[1, 2, 3] : null;
      },
    );
  });

  tearDown(() {
    ArtworkService.instance.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('no item, no saved thumbnail and nothing loaded: no real artwork', () {
    expect(hasRealArtwork(null), isFalse);
    expect(hasRealArtwork(_song(withArt)), isFalse);
    expect(hasRealArtwork(_song(withArt, artworkPath: '')), isFalse);
  });

  test('a saved thumbnail counts at once', () {
    expect(hasRealArtwork(_song(withoutArt, artworkPath: '/data/thumbs/2.jpg')), isTrue);
    expect(hasRealArtwork(_song(withoutArt, artworkPath: 'https://i.ytimg.com/vi/x/hq.jpg')), isTrue);
  });

  test('embedded art counts once it is loaded, at any size', () async {
    await ArtworkService.instance.getArtwork(withoutArt, size: 256);
    expect(ArtworkService.instance.hasCached(withoutArt), isFalse, reason: 'a miss is not art');
    expect(hasRealArtwork(_song(withoutArt)), isFalse);

    await ArtworkService.instance.getArtwork(withArt, size: 512);
    expect(ArtworkService.instance.hasCached(withArt), isTrue);
    expect(hasRealArtwork(_song(withArt)), isTrue);
    // A uri that only shares a prefix is a different song.
    expect(ArtworkService.instance.hasCached('content://media/external/audio/media/'), isFalse);
    expect(ArtworkService.instance.hasCached('content://media/external/audio'), isFalse);
    await ArtworkService.instance.getArtwork(withAtSign, size: 256);
    expect(ArtworkService.instance.hasCached(withAtSign), isTrue);
    expect(ArtworkService.instance.hasCached('file:///music/live'), isFalse);

    ArtworkService.instance.clearCache();
    expect(hasRealArtwork(_song(withArt)), isFalse);
  });
}
