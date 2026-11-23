import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the active network costs money per byte ("mediahub/network"):
/// Android's ConnectivityManager (NetworkChannel in MainActivity.kt), iPhone's
/// NWPathMonitor (AppDelegate.swift). Works without the personal tools.
class NetworkStatus {
  NetworkStatus({MethodChannel? channel}) : _channel = channel ?? defaultChannel;

  static const MethodChannel defaultChannel = MethodChannel('mediahub/network');

  final MethodChannel _channel;

  /// True on mobile data, a metered hotspot or Low Data Mode; false on an
  /// unmetered network; null when the phone cannot tell (no native side,
  /// no network, any error).
  Future<bool?> isMetered() async {
    try {
      return await _channel.invokeMethod<bool>('isMetered');
    } catch (_) {
      return null;
    }
  }
}

final networkStatusProvider = Provider<NetworkStatus>((ref) => NetworkStatus());
