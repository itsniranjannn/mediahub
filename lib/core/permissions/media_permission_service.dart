// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionState {
  checking,
  granted,
  limited,
  denied,
  permanentlyDenied,
}

abstract class MediaPermissionService {
  Future<MediaPermissionState> checkAudioPermission();
  Future<MediaPermissionState> checkVideoPermission();
  Future<MediaPermissionState> requestAudioPermission();
  Future<MediaPermissionState> requestVideoPermission();
  Future<bool> isVisualUserSelected();
  Future<bool> openSettings();
}

class MediaPermissionServiceImpl implements MediaPermissionService {
  final DeviceInfoPlugin _deviceInfo;

  /// Test seams: pretend to be Android at a given SDK level without a device.
  /// Production code passes neither and the real platform is used.
  final bool? _isAndroidOverride;
  final int? _androidSdkOverride;

  MediaPermissionServiceImpl({
    DeviceInfoPlugin? deviceInfo,
    @visibleForTesting bool? isAndroid,
    @visibleForTesting int? androidSdk,
  })  : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _isAndroidOverride = isAndroid,
        _androidSdkOverride = androidSdk;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;

  /// In automated widget tests platform channels do not respond unless mocked.
  /// A test that sets [_androidSdkOverride] mocks them itself.
  bool get _inUnmockedTest =>
      _androidSdkOverride == null && Platform.environment.containsKey('FLUTTER_TEST');

  Future<int> _getAndroidSdk() async {
    if (!_isAndroid) return 0;
    final sdkOverride = _androidSdkOverride;
    if (sdkOverride != null) return sdkOverride;
    if (_inUnmockedTest) return 33;
    try {
      final info = await _deviceInfo.androidInfo;
      return info.version.sdkInt;
    } catch (e) {
      debugPrint('[Permission] Failed getting Android SDK version: $e');
      return 33; // Default safely to modern permissions
    }
  }

  @override
  Future<bool> isVisualUserSelected() async {
    if (!_isAndroid || _inUnmockedTest) {
      return false;
    }
    final sdk = await _getAndroidSdk();
    if (sdk >= 34) {
      // Android 14+ "Select photos and videos": only video access matters here.
      // (Permission.photos / READ_MEDIA_IMAGES is not declared by the app, so
      // it is never checked.)
      final videoStatus = await Permission.videos.status;
      return videoStatus.isLimited;
    }
    return false;
  }

  @override
  Future<MediaPermissionState> checkAudioPermission() async {
    if (!_isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      final status = await Permission.audio.status;
      debugPrint('[Permission] checkAudioPermission (Android 13+, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      final status = await Permission.storage.status;
      debugPrint('[Permission] checkAudioPermission (Android <= 12, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<MediaPermissionState> checkVideoPermission() async {
    if (!_isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      final status = await Permission.videos.status;
      debugPrint('[Permission] checkVideoPermission (Android 13+, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      final status = await Permission.storage.status;
      debugPrint('[Permission] checkVideoPermission (Android <= 12, SDK $sdk): $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<MediaPermissionState> requestAudioPermission() async {
    if (!_isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      debugPrint('[Permission] Requesting Permission.audio (Android 13+, SDK $sdk)');
      final status = await Permission.audio.request();
      debugPrint('[Permission] Permission.audio result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      debugPrint('[Permission] Requesting Permission.storage (Android <= 12, SDK $sdk)');
      final status = await Permission.storage.request();
      debugPrint('[Permission] Permission.storage result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<MediaPermissionState> requestVideoPermission() async {
    if (!_isAndroid) {
      return MediaPermissionState.granted;
    }

    final sdk = await _getAndroidSdk();
    if (sdk >= 33) {
      debugPrint('[Permission] Requesting Permission.videos (Android 13+, SDK $sdk)');
      final status = await Permission.videos.request();
      debugPrint('[Permission] Permission.videos result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    } else {
      debugPrint('[Permission] Requesting Permission.storage (Android <= 12, SDK $sdk)');
      final status = await Permission.storage.request();
      debugPrint('[Permission] Permission.storage result: $status');
      if (status.isGranted) return MediaPermissionState.granted;
      if (status.isLimited) return MediaPermissionState.limited;
      if (status.isPermanentlyDenied) return MediaPermissionState.permanentlyDenied;
      return MediaPermissionState.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    return openAppSettings();
  }
}
