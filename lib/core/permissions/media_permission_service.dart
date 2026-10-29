import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
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
  final DeviceInfoPlugin _deviceInfo;

  MediaPermissionServiceImpl({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  Future<int> _getAndroidSdk() async {
    if (!Platform.isAndroid) return 0;
    // In automated widget tests, platform channels do not respond unless mocked
    if (Platform.environment.containsKey('FLUTTER_TEST')) return 33;
    try {
      final info = await _deviceInfo.androidInfo;
      return info.version.sdkInt;
    } catch (e) {
      debugPrint('[Permission] Failed getting Android SDK version: $e');
      return 33; // Default safely to modern permissions
    }
  }

  @override
  Future<MediaPermissionState> checkAudioPermission() async {
    // In automated widget test environment (or non-Android desktop), check without platform hanging
    if (!Platform.isAndroid || !Platform.isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      final status = await Permission.audio.status;
      debugPrint('[Permission] checkAudioPermission (Android 13+, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      final status = await Permission.storage.status;
      debugPrint('[Permission] checkAudioPermission (Android <= 12, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<MediaPermissionState> checkVideoPermission() async {
    if (!Platform.isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      final status = await Permission.videos.status;
      debugPrint('[Permission] checkVideoPermission (Android 13+, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      final status = await Permission.storage.status;
      debugPrint('[Permission] checkVideoPermission (Android <= 12, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<MediaPermissionState> requestAudioPermission() async {
    if (!Platform.isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      debugPrint('[Permission] Requesting Permission.audio (Android 13+, SDK $sdk)');
      final status = await Permission.audio.request();
      debugPrint('[Permission] Permission.audio result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      debugPrint('[Permission] Requesting Permission.storage (Android <= 12, SDK $sdk)');
      final status = await Permission.storage.request();
      debugPrint('[Permission] Permission.storage result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<MediaPermissionState> requestVideoPermission() async {
    if (!Platform.isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      debugPrint('[Permission] Requesting Permission.videos (Android 13+, SDK $sdk)');
      final status = await Permission.videos.request();
      debugPrint('[Permission] Permission.videos result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      debugPrint('[Permission] Requesting Permission.storage (Android <= 12, SDK $sdk)');
      final status = await Permission.storage.request();
      debugPrint('[Permission] Permission.storage result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    return openAppSettings();
  }
}
