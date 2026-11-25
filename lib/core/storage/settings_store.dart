// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny persistent key/value store (a JSON file in the app documents folder)
/// so settings survive an app restart. Reads are synchronous after [load].
///
/// Writes are safe against overlap and sudden kills:
/// - every save goes through one Future chain, so two writes never run at the
///   same time, and a queued write always stores the *latest* settings;
/// - the JSON goes to `settings.json.tmp` first and is then renamed over
///   `settings.json`, so the file is either the old or the new version, never
///   half-written;
/// - an unreadable (corrupt) `settings.json` is moved aside to
///   `settings.json.bad` instead of being silently overwritten (when even a
///   copy cannot be kept, the session stays memory-only).
///
/// Until [load] has found the file the store is memory-only (used by tests).
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  /// A fresh, independent store (tests point it at a temp directory with
  /// [loadFromDirectory]).
  @visibleForTesting
  factory SettingsStore.forTesting() => SettingsStore._();

  static const String fileName = 'settings.json';

  Map<String, dynamic> _data = {};
  File? _file;

  /// Tail of the write chain: each save runs after the previous one finished.
  Future<void> _writeChain = Future<void>.value();

  /// Bumped on every change; [_savedVersion] is the version last on disk.
  /// Lets queued writes that would store the same state again be skipped.
  int _version = 0;
  int _savedVersion = 0;

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await loadFromDirectory(dir);
    } catch (_) {
      _data = {};
    }
  }

  /// Loads `settings.json` from [dir] and saves there from now on.
  @visibleForTesting
  Future<void> loadFromDirectory(Directory dir) async {
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) {
      _file = file;
      return;
    }

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      // Could not even read it (I/O error): keep this session in memory only
      // rather than overwrite a file that may well be fine.
      debugPrint('[Settings] Could not read $fileName: $e');
      _data = {};
      _file = null;
      return;
    }

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('settings are not a JSON object');
      _data = Map<String, dynamic>.from(decoded);
    } on FormatException catch (e) {
      // Corrupt: keep it for inspection as settings.json.bad, then start
      // from defaults.
      debugPrint('[Settings] $fileName is corrupt ($e); keeping it as $fileName.bad');
      _data = {};
      final bad = '${file.path}.bad';
      try {
        await file.rename(bad);
      } catch (_) {
        try {
          // Could not move it: a copy is enough, the next save may then
          // replace the original.
          await file.copy(bad);
        } catch (copyError) {
          // Not even a copy: stay memory-only this session, so the corrupt
          // original is never overwritten.
          debugPrint('[Settings] Could not keep $fileName.bad ($copyError); settings stay in memory');
          _file = null;
          return;
        }
      }
    }
    _file = file;
  }

  bool getBool(String key, {bool defaultValue = false}) {
    final v = _data[key];
    return v is bool ? v : defaultValue;
  }

  Future<void> setBool(String key, bool value) async {
    _data[key] = value;
    await _save();
  }

  String? getString(String key) {
    final v = _data[key];
    return v is String ? v : null;
  }

  Future<void> setString(String key, String value) async {
    _data[key] = value;
    await _save();
  }

  List<String> getStringList(String key) {
    final v = _data[key];
    return v is List ? v.whereType<String>().toList() : <String>[];
  }

  Future<void> setStringList(String key, List<String> value) async {
    // Copy: a caller changing its list later must not change the settings.
    _data[key] = List<String>.of(value);
    await _save();
  }

  /// Forgets [key]: its default applies again.
  Future<void> remove(String key) async {
    if (!_data.containsKey(key)) return;
    _data.remove(key);
    await _save();
  }

  /// Queues a write of the current settings; completes once it is on disk
  /// (or has failed, which is never thrown: settings stay in memory).
  Future<void> _save() {
    final file = _file;
    if (file == null) return Future<void>.value(); // not loaded (tests): keep in memory only
    _version++;
    return _writeChain = _writeChain.then((_) => _writeLatest(file));
  }

  /// Writes the settings as they are *now* (latest state wins), atomically.
  Future<void> _writeLatest(File file) async {
    if (_savedVersion == _version) return; // an earlier queued write already stored this
    final version = _version;
    final tmp = File('${file.path}.tmp');
    try {
      // Encoded synchronously, so this is one consistent snapshot.
      final json = jsonEncode(_data);
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
      _savedVersion = version;
    } catch (e) {
      debugPrint('[Settings] Could not save $fileName: $e');
    }
  }
}
