import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';
import 'package:permission_handler/permission_handler.dart';

class MockMediaPermissionService implements MediaPermissionService {
  MediaPermissionState audioState = MediaPermissionState.denied;
  MediaPermissionState videoState = MediaPermissionState.denied;
  bool settingsOpened = false;

  @override
  Future<MediaPermissionState> checkAudioPermission() async => audioState;

  @override
  Future<MediaPermissionState> checkVideoPermission() async => videoState;

  @override
  Future<MediaPermissionState> requestAudioPermission() async {
    audioState = MediaPermissionState.granted;
    return audioState;
  }

  @override
  Future<MediaPermissionState> requestVideoPermission() async {
    videoState = MediaPermissionState.granted;
    return videoState;
  }

  @override
  Future<bool> isVisualUserSelected() async => false;

  @override
  Future<bool> openSettings() async {
    settingsOpened = true;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaPermissionService Mock Tests', () {
    late MockMediaPermissionService mockService;

    setUp(() {
      mockService = MockMediaPermissionService();
    });

    test('Initial permission state is denied', () async {
      expect(await mockService.checkAudioPermission(),
          equals(MediaPermissionState.denied));
      expect(await mockService.checkVideoPermission(),
          equals(MediaPermissionState.denied));
    });

    test('Request permission transitions to granted', () async {
      final state = await mockService.requestAudioPermission();
      expect(state, equals(MediaPermissionState.granted));
      expect(await mockService.checkAudioPermission(),
          equals(MediaPermissionState.granted));
    });

    test('Open settings triggers settings action', () async {
      final result = await mockService.openSettings();
      expect(result, isTrue);
      expect(mockService.settingsOpened, isTrue);
    });
  });

  group('MediaPermissionServiceImpl (Android, mocked permission channel)', () {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');

    // permission_handler's wire values.
    final storage = Permission.storage.value;
    final photos = Permission.photos.value;
    final videos = Permission.videos.value;
    final audio = Permission.audio.value;
    const denied = 0, granted = 1, limited = 3, permanentlyDenied = 4;

    /// Status the fake platform reports per permission (default: denied).
    late Map<int, int> statuses;
    /// Every permission the service checked or requested, in order.
    late List<int> checked;
    late List<int> requested;

    setUp(() {
      statuses = {};
      checked = [];
      requested = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            final p = call.arguments as int;
            checked.add(p);
            return statuses[p] ?? denied;
          case 'requestPermissions':
            final list = (call.arguments as List).cast<int>();
            requested.addAll(list);
            return {for (final p in list) p: statuses[p] ?? denied};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    MediaPermissionServiceImpl android(int sdk) =>
        MediaPermissionServiceImpl(isAndroid: true, androidSdk: sdk);

    test('not Android: everything is granted without asking the platform', () async {
      final service = MediaPermissionServiceImpl(isAndroid: false);
      expect(await service.checkAudioPermission(), MediaPermissionState.granted);
      expect(await service.checkVideoPermission(), MediaPermissionState.granted);
      expect(await service.requestAudioPermission(), MediaPermissionState.granted);
      expect(await service.requestVideoPermission(), MediaPermissionState.granted);
      expect(await service.isVisualUserSelected(), isFalse);
      expect(checked, isEmpty);
      expect(requested, isEmpty);
    });

    test('Android 13+: audio uses READ_MEDIA_AUDIO, video uses READ_MEDIA_VIDEO', () async {
      final service = android(33);
      statuses[audio] = granted;
      statuses[videos] = permanentlyDenied;

      expect(await service.checkAudioPermission(), MediaPermissionState.granted);
      expect(await service.checkVideoPermission(), MediaPermissionState.permanentlyDenied);
      expect(checked, [audio, videos]);

      statuses[videos] = granted;
      expect(await service.requestAudioPermission(), MediaPermissionState.granted);
      expect(await service.requestVideoPermission(), MediaPermissionState.granted);
      expect(requested, [audio, videos]);
    });

    test('Android 12 and older: audio and video both use storage', () async {
      final service = android(32);
      statuses[storage] = granted;

      expect(await service.checkAudioPermission(), MediaPermissionState.granted);
      expect(await service.checkVideoPermission(), MediaPermissionState.granted);
      expect(await service.requestAudioPermission(), MediaPermissionState.granted);
      expect(await service.requestVideoPermission(), MediaPermissionState.granted);
      expect(checked, [storage, storage]);
      expect(requested, [storage, storage]);
    });

    test('limited and denied map to their states', () async {
      final service = android(34);
      statuses[videos] = limited;
      expect(await service.checkVideoPermission(), MediaPermissionState.limited);
      expect(await service.checkAudioPermission(), MediaPermissionState.denied);
      expect(await service.requestAudioPermission(), MediaPermissionState.denied);
    });

    test('Android 14+: partial access is read from videos only, never photos', () async {
      final service = android(34);

      statuses[videos] = limited;
      expect(await service.isVisualUserSelected(), isTrue);

      statuses[videos] = granted;
      // Even if photos reported "limited", the app does not declare it.
      statuses[photos] = limited;
      expect(await service.isVisualUserSelected(), isFalse);

      expect(checked, [videos, videos]);
      expect(checked, isNot(contains(photos)));
    });

    test('Android 13 and older never report partial visual access', () async {
      expect(await android(33).isVisualUserSelected(), isFalse);
      expect(await android(30).isVisualUserSelected(), isFalse);
      expect(checked, isEmpty);
    });

    test('no flow ever checks or requests photos (READ_MEDIA_IMAGES)', () async {
      for (final sdk in [29, 32, 33, 34, 35]) {
        final service = android(sdk);
        await service.checkAudioPermission();
        await service.checkVideoPermission();
        await service.requestAudioPermission();
        await service.requestVideoPermission();
        await service.isVisualUserSelected();
      }
      expect(checked, isNot(contains(photos)));
      expect(requested, isNot(contains(photos)));
    });
  });
}
