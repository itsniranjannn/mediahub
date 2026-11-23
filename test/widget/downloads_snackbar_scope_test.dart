// A failed "Choose quality" lookup keeps its message (with Retry) on the
// Downloads screen only: it never covers Settings opened above it, and it is
// still there on coming back.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';
import 'package:mediahub/features/downloads/downloads_screen.dart';
import 'package:mediahub/features/downloads/web_link_download_flow.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

void main() {
  testWidgets('the lookup failure stays with Downloads and not over Settings', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          downloadsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          storageInfoProvider.overrideWith(
            (ref) => Future.value(const StorageInfo(usedBytes: 0, freeBytes: 1000000000)),
          ),
        ],
        child: MaterialApp(navigatorKey: navigator, theme: AppTheme.darkTheme, home: const DownloadsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // What the download flows do: ScaffoldMessenger.of(the screen's context).
    final screenContext = tester.element(find.byType(CustomScrollView).first);
    final messenger = ScaffoldMessenger.of(screenContext);
    expect(messenger.widget.key, DownloadsScreen.messengerKey);
    var retried = 0;
    WebLinkDownloadFlow.showLookupFailure(messenger, "Couldn't read this link", onRetry: () => retried++);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't read this link").hitTestable(), findsOneWidget);

    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('Settings page'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);
    expect(find.text("Couldn't read this link").hitTestable(), findsNothing);
    expect(find.text('Retry').hitTestable(), findsNothing);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text("Couldn't read this link").hitTestable(), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });
}
