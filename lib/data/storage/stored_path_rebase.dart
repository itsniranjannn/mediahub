import 'dart:io';

import 'package:path/path.dart' as p;

/// Points saved file paths at the app's current downloads folder after iOS
/// moved it.
///
/// iOS keeps an app's files in a container folder named by a random id:
/// `/var/mobile/Containers/Data/Application/<UUID>/Documents`. An update or a
/// reinstall over the old app (every week with a free Apple ID, or an iCloud
/// restore onto a new phone) moves the files into a container with a NEW id,
/// while the database still holds the absolute paths saved under the old one.
/// Every download, cover and saved queue entry would then be "missing", and a
/// delete would leave the real file behind.
///
/// [rebase] gives the path in the current folder for a path that points into
/// an older copy of the same folder: everything before and after the
/// container id is the same, only the id differs, and the file is really
/// there in the current folder. Anything else is left alone: phone files,
/// `content://` and `https://` addresses, paths outside the downloads folder,
/// paths already in the current folder (so running it twice changes nothing),
/// and any folder without an iOS container id (Android: paths never move, so
/// nothing is ever rewritten there).
class StoredPathRebaser {
  StoredPathRebaser({
    required String currentDownloadsDir,
    p.Context? context,
    bool Function(String path)? fileExists,
  })  : _ctx = context ?? p.context,
        _exists = fileExists ?? _fileExists {
    _currentDir = _ctx.normalize(currentDownloadsDir);
    _currentParts = _canonical(_ctx.split(_currentDir));
    _idIndex = _containerIdIndex(_currentParts);
  }

  final p.Context _ctx;
  final bool Function(String path) _exists;
  late final String _currentDir;
  late final List<String> _currentParts;

  /// Index of the container id in [_currentParts], or -1 when the current
  /// folder is not inside an iOS app container.
  late final int _idIndex;

  /// An iOS container id: an upper- or lower-case UUID.
  static final RegExp _containerId =
      RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$');

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// True when the current folder sits in an iOS app container, so stored
  /// paths can point into an older copy of it.
  bool get canRebase => _idIndex >= 0;

  /// A piece of text every path into any copy of the folder contains, such as
  /// `/Documents/downloads/`: narrows the database query to rows that may
  /// need a change. Null when [canRebase] is false.
  String? get marker {
    if (!canRebase) return null;
    final tail = _currentParts.sublist(_idIndex + 1);
    final sep = _ctx.separator;
    return tail.isEmpty ? sep : '$sep${tail.join(sep)}$sep';
  }

  /// The id sits right under `.../Containers/Data/Application/` (a phone)
  /// or the same folders inside a simulator's device folder. The last such
  /// segment wins.
  static int _containerIdIndex(List<String> parts) {
    for (var i = parts.length - 1; i > 0; i--) {
      if (parts[i - 1] == 'Application' && _containerId.hasMatch(parts[i])) return i;
    }
    return -1;
  }

  /// iOS reaches `/var` through `/private/var`: both spellings are the same
  /// folder, so they compare equal.
  List<String> _canonical(List<String> parts) {
    if (parts.length > 1 && parts[0] == '/' && parts[1] == 'private') {
      return [parts[0], ...parts.sublist(2)];
    }
    return parts;
  }

  /// [stored] moved to the current folder, or null when it stays as it is.
  String? rebase(String? stored) {
    if (!canRebase || stored == null || stored.isEmpty) return null;
    // content://, file://, https://: not a plain path the app saved.
    if (stored.contains('://')) return null;
    if (!_ctx.isAbsolute(stored)) return null;

    final parts = _canonical(_ctx.split(stored));
    if (parts.length <= _currentParts.length) return null;
    for (var i = 0; i < _currentParts.length; i++) {
      if (i == _idIndex) {
        if (!_containerId.hasMatch(parts[i])) return null;
      } else if (parts[i] != _currentParts[i]) {
        return null;
      }
    }
    // Already in the current folder.
    if (parts[_idIndex] == _currentParts[_idIndex]) return null;

    final rest = parts.sublist(_currentParts.length);
    if (rest.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    final candidate = _ctx.joinAll([_currentDir, ...rest]);
    return _exists(candidate) ? candidate : null;
  }
}
