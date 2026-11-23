import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/storage/settings_store.dart';
import 'package:mediahub/features/downloads/mobile_data_guard.dart';

const int _mb = 1024 * 1024;

void main() {
  group('shouldAskBeforeDownload', () {
    test('asks only for a known big size on metered data with the setting on', () {
      expect(shouldAskBeforeDownload(enabled: true, sizeBytes: 450 * _mb, metered: true), isTrue);
      expect(shouldAskBeforeDownload(enabled: true, sizeBytes: 100 * _mb, metered: true), isFalse);
      expect(shouldAskBeforeDownload(enabled: true, sizeBytes: null, metered: true), isFalse);
      expect(shouldAskBeforeDownload(enabled: true, sizeBytes: 450 * _mb, metered: false), isFalse);
      expect(shouldAskBeforeDownload(enabled: true, sizeBytes: 450 * _mb, metered: null), isFalse);
      expect(shouldAskBeforeDownload(enabled: false, sizeBytes: 450 * _mb, metered: true), isFalse);
    });

    test('wording', () {
      expect(bigDownloadQuestion(450 * _mb), 'This is 450 MB on mobile data. Download now?');
      expect(mobileDataSizeLabel(1536 * _mb), '1.5 GB');
    });
  });

  group('confirmBigDownloadOnMobileData', () {
    setUp(() => SettingsStore.instance.remove(AskBeforeBigDownloadsNotifier.prefKey));

    Future<Future<bool>> start(WidgetTester tester, {required bool? metered, int? size, bool enabled = true}) async {
      var networkAsked = 0;
      final container = ProviderContainer(overrides: [
        meteredNetworkCheckProvider.overrideWithValue(() async {
          networkAsked++;
          return metered;
        }),
      ]);
      addTearDown(container.dispose);
      if (!enabled) container.read(askBeforeBigDownloadsProvider.notifier).set(false);
      late Future<bool> result;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => result = confirmBigDownloadOnMobileData(context, ref, size),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (size == null || size <= bigDownloadBytes) expect(networkAsked, 0, reason: 'small or unknown: no network check');
      return result;
    }

    testWidgets('big file on mobile data: Download starts it', (tester) async {
      final result = await start(tester, metered: true, size: 450 * _mb);
      expect(find.text('This is 450 MB on mobile data. Download now?'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('Wait for Wi-Fi does not start it', (tester) async {
      final result = await start(tester, metered: true, size: 450 * _mb);
      await tester.tap(find.text('Wait for Wi-Fi'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('no question on Wi-Fi, unknown network, unknown size, or with the switch off', (tester) async {
      for (final (metered, size, enabled) in [
        (false, 450 * _mb, true),
        (null, 450 * _mb, true),
        (true, null, true),
        (true, 50 * _mb, true),
        (true, 450 * _mb, false),
      ]) {
        final result = await start(tester, metered: metered, size: size, enabled: enabled);
        expect(find.byType(AlertDialog), findsNothing);
        expect(await result, isTrue);
      }
    });
  });
}
