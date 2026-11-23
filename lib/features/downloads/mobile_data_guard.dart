import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/network_status.dart';
import '../../core/storage/settings_store.dart';

/// "Ask before big downloads on mobile data": before a download whose size is
/// known and over [bigDownloadBytes] starts while the phone is on metered data
/// (mobile data, a metered hotspot), MediaHub asks first. Unknown size or an
/// unknown network: no question. "Wait for Wi-Fi" simply does not start it.
const int bigDownloadBytes = 100 * 1024 * 1024;

/// True when the question must be asked.
bool shouldAskBeforeDownload({required bool enabled, required int? sizeBytes, required bool? metered}) =>
    enabled && sizeBytes != null && sizeBytes > bigDownloadBytes && metered == true;

/// "450 MB", "1.2 GB" (1024-based, like the rest of the app).
String mobileDataSizeLabel(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  return '${(bytes / mb).round()} MB';
}

String bigDownloadQuestion(int bytes) => 'This is ${mobileDataSizeLabel(bytes)} on mobile data. Download now?';

class AskBeforeBigDownloadsNotifier extends Notifier<bool> {
  static const String prefKey = 'ask_big_downloads_mobile_data';

  @override
  bool build() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  void set(bool value) {
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
  }
}

final askBeforeBigDownloadsProvider =
    NotifierProvider<AskBeforeBigDownloadsNotifier, bool>(AskBeforeBigDownloadsNotifier.new);

/// Whether the active network is metered ("mediahub/network": Android's
/// ConnectivityManager, iPhone's NWPathMonitor), with or without the personal
/// tools; null = unknown (then no question is asked).
final meteredNetworkCheckProvider = Provider<Future<bool?> Function()>((ref) {
  final network = ref.watch(networkStatusProvider);
  return () async {
    try {
      return await network.isMetered();
    } catch (_) {
      return null;
    }
  };
});

/// Returns true when the download of [sizeBytes] may start: no question was
/// needed, or the user chose Download. False for "Wait for Wi-Fi" (or the
/// dialog was dismissed, or the screen went away).
Future<bool> confirmBigDownloadOnMobileData(BuildContext context, WidgetRef ref, int? sizeBytes) async {
  final enabled = ref.read(askBeforeBigDownloadsProvider);
  // Cheap checks first: the network is only asked about for a big file.
  if (!shouldAskBeforeDownload(enabled: enabled, sizeBytes: sizeBytes, metered: true)) return true;
  final metered = await ref.read(meteredNetworkCheckProvider)();
  if (!shouldAskBeforeDownload(enabled: enabled, sizeBytes: sizeBytes, metered: metered)) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mobile data'),
      content: Text(bigDownloadQuestion(sizeBytes!)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Wait for Wi-Fi')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Download')),
      ],
    ),
  );
  return go == true && context.mounted;
}
