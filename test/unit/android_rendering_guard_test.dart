// The Samsung (Adreno, Android 13) "only YouTube on screen" freeze after a
// swipe-away: hybrid composition left Flutter's GL context current on the
// platform thread, so every frame on the reopened Activity failed with
// EGL_BAD_ACCESS. The Online WebView uses texture-layer composition instead,
// and the manifest carries no renderer meta-data (EnableImpeller=false was
// ignored by this engine; forcing Vulkan onto a deny-listed driver is worse).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/online/online_web_view.dart';

void main() {
  test('the manifest does not pick the renderer', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('android:name="io.flutter.embedding.android.EnableImpeller"')));
    expect(manifest, isNot(contains('android:name="io.flutter.embedding.android.ImpellerBackend"')));
    expect(manifest, isNot(contains('android:taskAffinity=""')));
  });

  test('the Online WebView never uses hybrid composition', () {
    expect(onlineWebViewSettings(backgroundPlay: true, isIOS: false).useHybridComposition, isFalse);
  });
}
