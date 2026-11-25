// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import AVFoundation
import Flutter
import Network
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // MediaHub's own channels, kept alive for the engine's lifetime.
  private var backupFiles: BackupFilesChannel?
  private var network: NetworkChannel?
  private var phoneMedia: PhoneMediaChannel?

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
      phoneMedia?.cleanup()
      backupFiles = BackupFilesChannel(messenger: messenger)
      network = NetworkChannel(messenger: messenger)
      phoneMedia = PhoneMediaChannel(messenger: messenger)
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

/// "mediahub/phone_media", the iPhone side of PhoneMediaChannel.kt ("Save to phone").
/// - capabilities -> {canSaveToPhone: true, systemAsksBeforeDelete: false}
/// - saveToPhone {path, kind} -> a path. Only files inside Documents/downloads (MediaHub's
///   own downloads) are accepted. Audio: nothing moves; Documents is shared with the
///   Files app (UIFileSharingEnabled), so the path itself comes back. Video: a copy is
///   added to Photos (PHPhotoLibrary, add-only access, NSPhotoLibraryAddUsageDescription)
///   and the path comes back (MediaHub keeps its own copy to play it).
///   Errors: BAD_ARGS, NOT_ALLOWED (no Photos access), UNSUPPORTED (a format Photos does
///   not take, such as WebM or MKV), SAVE_FAILED.
/// - deleteFromPhone -> false: the iPhone app never sees the phone's own media, so it can
///   only delete its own downloads (done in Dart).
/// - readLyricsSidecar -> nil.
final class PhoneMediaChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mediahub/phone_media", binaryMessenger: messenger)
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
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result(["sdk": 0, "canSaveToPhone": true, "systemAsksBeforeDelete": false])
    case "saveToPhone":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let path = args["path"] as? String, let kind = args["kind"] as? String,
        kind == "audio" || kind == "video"
      else {
        result(FlutterError(code: "BAD_ARGS", message: "path and kind are needed", details: nil))
        return
      }
      guard let file = PhoneMediaChannel.ownDownload(path) else {
        result(FlutterError(code: "BAD_ARGS", message: "Not a MediaHub download", details: nil))
        return
      }
      if kind == "audio" {
        // Already in the Files app (On My iPhone -> MediaHub -> downloads).
        result(file.path)
        return
      }
      saveVideoToPhotos(file, result: result)
    case "deleteFromPhone":
      result(false)
    case "readLyricsSidecar":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The file when it lies inside Documents/downloads, else nil (no "..", no symlinks out).
  private static func ownDownload(_ path: String) -> URL? {
    guard
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return nil }
    let root = docs.appendingPathComponent("downloads", isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL.path
    let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    guard file.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: file.path) else {
      return nil
    }
    return file
  }

  private func saveVideoToPhotos(_ file: URL, result: @escaping FlutterResult) {
    guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(file.path) else {
      result(FlutterError(code: "UNSUPPORTED", message: "Photos cannot take this video format", details: nil))
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "NOT_ALLOWED", message: "No access to Photos", details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
      }) { ok, error in
        DispatchQueue.main.async {
          if ok {
            result(file.path)
          } else {
            result(FlutterError(code: "SAVE_FAILED", message: error?.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}
