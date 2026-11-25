// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import AVFoundation
import Flutter
import Network
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // MediaHub's own channels, kept alive for the engine's lifetime.
  private var backupFiles: BackupFilesChannel?
  private var network: NetworkChannel?

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
    // MediaHub's own method channels (the iPhone sides of BackupFilesChannel.kt
    // and NetworkChannel.kt), on the same engine's messenger.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MediaHubChannels") {
      let messenger = registrar.messenger()
      backupFiles?.cleanup()
      network?.cleanup()
      backupFiles = BackupFilesChannel(messenger: messenger)
      network = NetworkChannel(messenger: messenger)
    }
  }
}

/// The view controller on top, to present the document picker from.
private func topViewController() -> UIViewController? {
  let windows = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
  var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
  while let presented = top?.presentedViewController, !presented.isBeingDismissed {
    top = presented
  }
  return top
}

/// Library backup files ("mediahub/backup_files"), the iPhone side of
/// BackupFilesChannel.kt, through UIDocumentPickerViewController:
/// - save {fileName, bytes} -> true when saved, false when the user backed out;
/// - open {maxBytes} -> the file's bytes, nil when the user backed out,
///   error TOO_LARGE past maxBytes.
/// Other errors: NO_ACTIVITY (nothing on screen), BUSY, BAD_ARGS, IO.
/// The picker grants access to the one file the user picked only.
final class BackupFilesChannel: NSObject, UIDocumentPickerDelegate {
  private enum Mode { case save, open }

  private let channel: FlutterMethodChannel
  private let io = DispatchQueue(label: "mediahub.backup_files")
  private var pending: FlutterResult?
  private var mode: Mode = .save
  private var maxBytes = 5 * 1024 * 1024
  private var tempDir: URL?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mediahub/backup_files", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
  }

  func cleanup() {
    channel.setMethodCallHandler(nil)
    pending?(nil)
    pending = nil
    removeTemp()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "save" || call.method == "open" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "NO_ACTIVITY", message: "MediaHub is not on screen", details: nil))
      return
    }
    if pending != nil {
      result(FlutterError(code: "BUSY", message: "A file picker is already open", details: nil))
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    let picker: UIDocumentPickerViewController
    if call.method == "save" {
      guard let data = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "BAD_ARGS", message: "Nothing to save", details: nil))
        return
      }
      // Only a plain file name: no folders from the Dart side.
      let given = ((args["fileName"] as? String) ?? "") as NSString
      let name = given.lastPathComponent
      let fileName = name.isEmpty || name == "/" ? "mediahub-backup.json" : name
      do {
        let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        let file = dir.appendingPathComponent(fileName)
        try data.data.write(to: file, options: .atomic)
        picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      } catch {
        removeTemp()
        result(FlutterError(code: "IO", message: error.localizedDescription, details: nil))
        return
      }
      mode = .save
    } else {
      maxBytes = (args["maxBytes"] as? NSNumber)?.intValue ?? (5 * 1024 * 1024)
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data], asCopy: false)
      picker.allowsMultipleSelection = false
      mode = .open
    }
    picker.delegate = self
    pending = result
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(mode == .save ? false : nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if mode == .save {
      finish(!urls.isEmpty)
      return
    }
    guard let url = urls.first else {
      finish(nil)
      return
    }
    let max = maxBytes
    io.async { [weak self] in
      let outcome = BackupFilesChannel.read(url, maxBytes: max)
      DispatchQueue.main.async { self?.finish(outcome) }
    }
  }

  /// The file's bytes (FlutterStandardTypedData) or a FlutterError.
  private static func read(_ url: URL, maxBytes: Int) -> Any {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let tooLarge = FlutterError(code: "TOO_LARGE", message: "The file is too large", details: nil)
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
      return tooLarge
    }
    var coordError: NSError?
    var outcome: Any = FlutterError(code: "IO", message: "Could not read the file", details: nil)
    // A coordinated read, so a file still in iCloud Drive is fetched first.
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
      do {
        let handle = try FileHandle(forReadingFrom: readURL)
        defer { try? handle.close() }
        // One byte past the limit is enough to know it is too large.
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        outcome = data.count > maxBytes ? tooLarge : FlutterStandardTypedData(bytes: data)
      } catch {
        outcome = FlutterError(code: "IO", message: error.localizedDescription, details: nil)
      }
    }
    if let coordError = coordError {
      return FlutterError(code: "IO", message: coordError.localizedDescription, details: nil)
    }
    return outcome
  }

  private func finish(_ value: Any?) {
    let result = pending
    pending = nil
    removeTemp()
    result?(value)
  }

  private func removeTemp() {
    if let dir = tempDir {
      try? FileManager.default.removeItem(at: dir)
    }
    tempDir = nil
  }
}

/// "mediahub/network": isMetered -> true on mobile data, a network the iPhone
/// counts as expensive (a personal hotspot) or Low Data Mode; false otherwise;
/// nil while there is no network or no answer yet. The iPhone side of
/// NetworkChannel.kt.
final class NetworkChannel {
  private let channel: FlutterMethodChannel
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "mediahub.network")
  private var latest: NWPath?  // Only touched on `queue`.

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mediahub/network", binaryMessenger: messenger)
    monitor.pathUpdateHandler = { [weak self] path in
      self?.latest = path
    }
    monitor.start(queue: queue)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "isMetered" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.isMetered())
    }
  }

  func cleanup() {
    channel.setMethodCallHandler(nil)
    monitor.cancel()
  }

  private func isMetered() -> Bool? {
    let path: NWPath? = queue.sync { latest }
    guard let path = path, path.status == .satisfied else { return nil }
    return path.isExpensive || path.isConstrained || path.usesInterfaceType(.cellular)
  }
}
