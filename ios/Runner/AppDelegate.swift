import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Playback category from the first moment, so sound (local music and the
    // Online tab's YouTube page) keeps going when the screen locks; audio_session
    // configures the same category again once Dart starts. Not activated here:
    // that would interrupt other apps' audio at launch.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
