import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahub/app/app.dart';
import 'package:mediahub/core/app_config.dart';

void main() {
  testWidgets('Smoke test MediaHubApp renders correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MediaHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppConfig.appName), findsWidgets);
  });
}
