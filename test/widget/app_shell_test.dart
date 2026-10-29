import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahub/app/app.dart';
import 'package:mediahub/core/app_config.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import '../unit/permission_service_test.dart';

void main() {
  testWidgets('MediaHubApp launches and navigates through tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaPermissionServiceProvider.overrideWithValue(MockMediaPermissionService()),
        ],
        child: const MediaHubApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(AppConfig.appName), findsWidgets);

    // Tap Music tab
    await tester.tap(find.text('Music'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Permission Required'), findsOneWidget);

    // Tap Videos tab
    await tester.tap(find.text('Videos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Permission Required'), findsOneWidget);

    // Tap Downloads tab
    await tester.tap(find.text('Downloads'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
        find.text(
            'Active and completed downloads in ${AppConfig.appName} will appear here.'),
        findsOneWidget);

    // Tap Settings tab
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Configure your ${AppConfig.appName} preferences.'),
        findsOneWidget);
  });
}
