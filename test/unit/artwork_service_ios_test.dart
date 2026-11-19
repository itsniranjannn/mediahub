// Covers on iPhone (iOS parity P3, task 2): the 'mediahub/media_store'
// channel is Android only, so on iPhone ArtworkService never calls it and
// reads the cover embedded in a downloaded file instead, only for files in
// MediaHub's own folders, scaled down for the lookup size, and cached like
// the Android covers. Android still asks the channel.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform_info.dart';
import 'package:mediahub/core/services/artwork_service.dart';

const _channel = MethodChannel('mediahub/media_store');

/// A real PNG of [width] x [height], drawn by the engine.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF6A3FB5),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<(int, int)> _sizeOf(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = (descriptor.width, descriptor.height);
  descriptor.dispose();
  buffer.dispose();
  return size;
}

List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _syncSafe(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

/// An MP3 with [cover] as its ID3v2.3 front cover.
List<int> _mp3(Uint8List cover) {
  final apic = [0, ...ascii.encode('image/png'), 0, 3, 0, ...cover];
  final body = [...ascii.encode('APIC'), ..._be32(apic.length), 0, 0, ...apic, ...List.filled(16, 0)];
  return [...ascii.encode('ID3'), 3, 0, 0, ..._syncSafe(body.length), ...body, 0xFF, 0xFB, 0x90, 0x00];
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appFolder;
  late Directory elsewhere;
  late List<MethodCall> channelCalls;
  final service = ArtworkService.instance;

  setUp(() async {
    appFolder = await Directory.systemTemp.createTemp('mediahub_app_');
    elsewhere = await Directory.systemTemp.createTemp('mediahub_other_');
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      channelCalls.add(call);
      return <int>[9, 9, 9];
    });
    PlatformInfo.debugIsIOS = true;
    ArtworkService.debugAppFolders = () async => [appFolder.path];
    service.clearCache();
  });

  tearDown(() async {
    PlatformInfo.resetForTests();
    ArtworkService.debugAppFolders = null;
    ArtworkService.scaleTimeout = const Duration(seconds: 3);
    binding.handleAppLifecycleStateChanged(ui.AppLifecycleState.resumed);
    service.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    await appFolder.delete(recursive: true);
    await elsewhere.delete(recursive: true);
  });

  Future<String> save(Directory folder, String name, List<int> bytes) async {
    final downloads = Directory('${folder.path}${Platform.pathSeparator}downloads');
    await downloads.create(recursive: true);
    final file = File('${downloads.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test('a downloaded song: its embedded cover, without the Android channel, then from the cache', () async {
    final cover = await _png(200, 200);
    final path = await save(appFolder, 'Resham Firiri.mp3', _mp3(cover));

    final bytes = await service.getArtwork(path, size: 256);
    expect(bytes, cover, reason: 'small enough for 256: handed over as it is');
    expect(channelCalls, isEmpty, reason: 'the channel has no iPhone side');
    expect(service.hasCached(path), isTrue);
    expect(service.peek(path, size: 256), cover);

    // The file can go: the cache answers.
    await File(path).delete();
    expect(await service.getArtwork(path, size: 256), cover);
  });

  test('a file:// uri works the same', () async {
    final cover = await _png(64, 64);
    final path = await save(appFolder, 'song.mp3', _mp3(cover));
    expect(await service.getArtwork(Uri.file(path).toString(), size: 256), cover);
    expect(channelCalls, isEmpty);
  });

  test('a large cover is scaled down to the lookup size', () async {
    final path = await save(appFolder, 'big.mp3', _mp3(await _png(1200, 800)));
    final bytes = await service.getArtwork(path, size: 256);
    expect(bytes, isNotNull);
    expect(await _sizeOf(bytes!), (256, 171));
  });

  test('in the background (the lock screen asking for the next cover) the cover goes out as it is, uncached', () async {
    // iOS gives Flutter no GPU in the background: scaling would wait until
    // the app is opened again, and the lock screen would show no cover.
    final cover = await _png(1200, 800);
    final path = await save(appFolder, 'big.mp3', _mp3(cover));

    binding.handleAppLifecycleStateChanged(ui.AppLifecycleState.paused);
    expect(await service.getArtwork(path, size: 512), cover);
    expect(service.peek(path, size: 512), isNull, reason: 'not kept: the list scales it once the app is open');
    expect(service.isKnownMissing(path, size: 512), isFalse);

    binding.handleAppLifecycleStateChanged(ui.AppLifecycleState.resumed);
    final scaled = await service.getArtwork(path, size: 512);
    expect(await _sizeOf(scaled!), (512, 341));
    expect(service.peek(path, size: 512), scaled);
  });

  test('scaling that takes too long hands the cover over as it is, uncached', () async {
    final cover = await _png(1200, 800);
    final path = await save(appFolder, 'slow.mp3', _mp3(cover));
    ArtworkService.scaleTimeout = Duration.zero;
    expect(await service.getArtwork(path, size: 256), cover);
    expect(service.peek(path, size: 256), isNull);
    expect(service.isKnownMissing(path, size: 256), isFalse);
  });

  test('web links, content:// uris and files outside MediaHub are never read, and never sent to the channel', () async {
    final outside = await save(elsewhere, 'song.mp3', _mp3(await _png(32, 32)));
    final sneaky = '${appFolder.path}${Platform.pathSeparator}..${Platform.pathSeparator}'
        '${elsewhere.uri.pathSegments.where((s) => s.isNotEmpty).last}'
        '${Platform.pathSeparator}downloads${Platform.pathSeparator}song.mp3';
    for (final uri in [
      outside,
      sneaky,
      'content://media/external/audio/media/1',
      'https://i.ytimg.com/vi/x/hqdefault.jpg',
      'downloads/song.mp3',
    ]) {
      expect(await service.getArtwork(uri, size: 256), isNull, reason: uri);
      expect(service.isKnownMissing(uri, size: 256), isTrue, reason: 'answered at once next time: $uri');
    }
    expect(channelCalls, isEmpty);
  });

  test('a song without a cover, or a missing file, is a remembered miss', () async {
    final path = await save(appFolder, 'plain.mp3', [0xFF, 0xFB, 0x90, 0x00, ...List.filled(64, 0)]);
    expect(await service.getArtwork(path, size: 256), isNull);
    expect(service.isKnownMissing(path, size: 256), isTrue);
    final gone = '${appFolder.path}${Platform.pathSeparator}gone.mp3';
    expect(await service.getArtwork(gone, size: 256), isNull);
    expect(channelCalls, isEmpty);
  });

  test('Android is unchanged: the channel answers, nothing is read from the file', () async {
    PlatformInfo.debugIsIOS = false;
    final path = await save(appFolder, 'song.mp3', _mp3(await _png(32, 32)));
    expect(await service.getArtwork(path, size: 256), Uint8List.fromList([9, 9, 9]));
    expect(channelCalls.single.method, 'getArtwork');
    expect(channelCalls.single.arguments, {'uri': path, 'width': 256, 'height': 256});
  });
}
