import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/features/settings/diagnostics_screen.dart';

void main() {
  setUp(() {
    DiagnosticsService.enableDebounce = false;
  });

  testWidgets('DiagnosticsScreen renders null-safely with dataless events', (tester) async {
    final diagnostics = DiagnosticsService.instance;
    await diagnostics.clear();

    // Log events with no payload (e.g. seek, service_start)
    diagnostics.logEvent('service_start');
    diagnostics.logEvent('seek');
    diagnostics.logEvent('play', {'caller': 'in_app'});

    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('service_start'), findsOneWidget);
    expect(find.text('seek'), findsOneWidget);
    expect(find.text('play'), findsOneWidget);
    expect(find.text('caller: in_app'), findsOneWidget);
  });
}

