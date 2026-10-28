import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionState {
  granted,
  denied,
  permanentlyDenied,
}

abstract class MediaPermissionService {
  Future<MediaPermissionState> checkAudioPermission();
  Future<MediaPermissionState> checkVideoPermission();
  Future<MediaPermissionState> requestAudioPermission();
  Future<MediaPermissionState> requestVideoPermission();
  Future<bool> openSettings();
}

class MediaPermissionServiceImpl implements MediaPermissionService {
  @override
  Future<MediaPermissionState> checkAudioPermission() async {
    final audioStatus = await Permission.audio.status;
    final storageStatus = await Permission.storage.status;

    if (audioStatus.isGranted || storageStatus.isGranted) {
      return MediaPermissionState.granted;
    }
    if (audioStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    return MediaPermissionState.denied;
  }

  @override
  Future<MediaPermissionState> checkVideoPermission() async {
    final videoStatus = await Permission.videos.status;
    final storageStatus = await Permission.storage.status;

    if (videoStatus.isGranted || storageStatus.isGranted) {
      return MediaPermissionState.granted;
    }
    if (videoStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    return MediaPermissionState.denied;
  }

  @override
  Future<MediaPermissionState> requestAudioPermission() async {
    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) return MediaPermissionState.granted;

    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) return MediaPermissionState.granted;

    if (audioStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    return MediaPermissionState.denied;
  }

  @override
  Future<MediaPermissionState> requestVideoPermission() async {
    final videoStatus = await Permission.videos.request();
    if (videoStatus.isGranted) return MediaPermissionState.granted;

    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) return MediaPermissionState.granted;

    if (videoStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    return MediaPermissionState.denied;
  }

  @override
  Future<bool> openSettings() async {
    return openAppSettings();
  }
}
