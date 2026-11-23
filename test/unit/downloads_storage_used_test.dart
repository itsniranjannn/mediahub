import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/domain/models/download_state.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/downloads/downloads_notifier.dart';

DownloadsTableCompanion _row(String id, int bytes, DownloadTaskState state) {
  final now = DateTime(2026, 11, 23);
  return DownloadsTableCompanion.insert(
    id: id,
    url: 'https://example.com/$id.mp3',
    host: 'example.com',
    displayName: id,
    fileName: '$id.mp3',
    state: state.name,
    receivedBytes: Value(bytes),
    createdAt: now,
    updatedAt: now,
  );
}

Future<int> _usedAfterSettle(ProviderContainer c) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return (await c.read(storageInfoProvider.future)).usedBytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('"MB used" follows downloads that finish and are deleted, while the tab stays open', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    final sub = c.listen(storageInfoProvider, (_, _) {});
    addTearDown(sub.close);

    expect(await _usedAfterSettle(c), 0);

    await db.into(db.downloadsTable).insert(_row('a', 3 * 1024 * 1024, DownloadTaskState.completed));
    expect(await _usedAfterSettle(c), 3 * 1024 * 1024);

    // A download still running does not count yet; it does once it finishes.
    await db.into(db.downloadsTable).insert(_row('b', 1024 * 1024, DownloadTaskState.downloading));
    expect(await _usedAfterSettle(c), 3 * 1024 * 1024);
    await (db.update(db.downloadsTable)..where((t) => t.id.equals('b')))
        .write(DownloadsTableCompanion(state: Value(DownloadTaskState.completed.name)));
    expect(await _usedAfterSettle(c), 4 * 1024 * 1024);

    await (db.delete(db.downloadsTable)..where((t) => t.id.equals('a'))).go();
    expect(await _usedAfterSettle(c), 1024 * 1024);
  });
}
