// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/downloads/download_link_inbox.dart';
import 'package:mediahub/features/downloads/shared_link.dart';

class _FakeSource implements SharedTextSource {
  final controller = StreamController<String>.broadcast();
  @override
  Stream<String> get texts => controller.stream;
}

final _messenger = GlobalKey<ScaffoldMessengerState>();
final _page = ValueNotifier<String>('home');

/// The router's wiring in small: a good link opens "Downloads", a refused
/// share shows a snackbar.
final _wiringProvider = Provider<int>((ref) {
  final sub = listenForSharedLinks(
    ref,
    openDownloads: () => _page.value = 'downloads',
    showMessage: (m) => _messenger.currentState?.showSnackBar(SnackBar(content: Text(m))),
  );
  ref.onDispose(sub.cancel);
  return 0;
});

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_wiringProvider);
    final link = ref.watch(downloadLinkInboxProvider);
    return MaterialApp(
      scaffoldMessengerKey: _messenger,
      home: Scaffold(
        body: ValueListenableBuilder<String>(
          valueListenable: _page,
          builder: (_, page, _) => Text(page == 'downloads' ? 'Downloads: ${link?.url}' : 'Home'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a shared link opens Downloads; plain text shows a friendly note', (tester) async {
    final source = _FakeSource();
    await tester.pumpWidget(
      ProviderScope(overrides: [sharedTextSourceProvider.overrideWithValue(source)], child: const _Host()),
    );

    source.controller.add('a recipe for momo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(SharedLinkMessages.noLink), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    source.controller.add('https://192.168.1.4/private.mp4');
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);

    source.controller.add('Check this https://www.instagram.com/reel/xyz/');
    await tester.pump();
    await tester.pump();
    expect(find.text('Downloads: https://www.instagram.com/reel/xyz/'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
