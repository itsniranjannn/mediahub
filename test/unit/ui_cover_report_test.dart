import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/platform/device_controls.dart';

void main() {
  group('UiCoverReport: does the WebView cover the Flutter UI', () {
    test('a healthy window: one FlutterView, a wrapper with its texture, nothing else', () {
      final r = UiCoverReport.fromMap(const {'orphanWrappers': 0, 'wrappers': 1, 'flutterViews': 1, 'strayViews': []});
      expect(r.covers(pageFullscreen: false), isFalse);
    });

    test('a wrapper without a render target draws the page over everything', () {
      final r = UiCoverReport.fromMap(const {'orphanWrappers': 1, 'wrappers': 1, 'flutterViews': 1, 'strayViews': []});
      expect(r.covers(pageFullscreen: false), isTrue);
      expect(r.covers(pageFullscreen: true), isTrue);
    });

    test('a fullscreen view is expected only while the page is fullscreen', () {
      final r = UiCoverReport.fromMap(const {'wrappers': 1, 'flutterViews': 1, 'strayViews': ['decor:android.widget.FrameLayout']});
      expect(r.covers(pageFullscreen: true), isFalse);
      expect(r.covers(pageFullscreen: false), isTrue);
    });

    test('no FlutterView (or two) in the window counts as covered', () {
      expect(const UiCoverReport(flutterViews: 0).covers(pageFullscreen: false), isTrue);
      expect(const UiCoverReport(flutterViews: 2).covers(pageFullscreen: false), isTrue);
    });

    test('a missing map entry falls back to healthy values', () {
      final r = UiCoverReport.fromMap(const {});
      expect(r.covers(pageFullscreen: false), isFalse);
      expect(r.toDiagnostics()['flutter_views'], 1);
    });
  });
}
