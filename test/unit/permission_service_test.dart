import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/permissions/media_permission_service.dart';

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
  Future<bool> openSettings() async {
    settingsOpened = true;
    return true;
  }
}

void main() {
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
}
