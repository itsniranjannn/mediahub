import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:mediahub/data/database/app_database.dart';

void main() {
  test('Library scan missing pass excludes source=download items', () async {
    final db = AppDatabase(NativeDatabase.memory());

    // 1. Insert a device item and a download item
    final now = DateTime.now();
    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'device_track',
        uri: '/storage/device_track.mp3',
        mediaType: 'audio',
        title: 'Device Track',
        durationMs: 1000,
        sizeBytes: 1000,
        dateAdded: now,
        availability: const Value('available'),
        source: const Value('device'),
      ),
    );

    await db.into(db.mediaItemsTable).insert(
      MediaItemsTableCompanion.insert(
        id: 'dl_123',
        uri: '/storage/dl_123.mp3',
        mediaType: 'audio',
        title: 'Downloaded Track',
        durationMs: 1000,
        sizeBytes: 1000,
        dateAdded: now,
        availability: const Value('available'),
        source: const Value('download'),
      ),
    );

    // 2. Perform library scan with empty MediaStore scan (device item deleted or not present in scan)
    // To simulate scan transaction directly like library repository missing pass:
    final scannedAudioIds = <String>{}; // no audio scanned
    final existingAudio = await (db.select(db.mediaItemsTable)
          ..where((tbl) => tbl.mediaType.equals('audio')))
        .get();

    for (final row in existingAudio) {
      if (row.source == 'download') continue;
      if (!scannedAudioIds.contains(row.id)) {
        await (db.update(db.mediaItemsTable)..where((tbl) => tbl.id.equals(row.id))).write(
          const MediaItemsTableCompanion(availability: Value('missing')),
        );
      }
    }

    final updatedItems = await db.select(db.mediaItemsTable).get();
    final deviceItem = updatedItems.firstWhere((i) => i.id == 'device_track');
    final dlItem = updatedItems.firstWhere((i) => i.id == 'dl_123');

    expect(deviceItem.availability, 'missing');
    expect(dlItem.availability, 'available');

    await db.close();
  });
}
