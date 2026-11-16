import 'package:drift/drift.dart';
import 'package:mediahub/data/database/app_database.dart';

/// In-memory [AppDatabase] that can be told to throw when a download is being
/// finalized: both engines insert the library row (media_items) only then, so
/// [failMediaInsert] simulates a database error in the middle of finalizing.
class FailingFinalizeDatabase extends AppDatabase {
  FailingFinalizeDatabase(super.e);

  bool failMediaInsert = false;

  @override
  InsertStatement<T, D> into<T extends Table, D>(TableInfo<T, D> table) {
    if (failMediaInsert && table.actualTableName == mediaItemsTable.actualTableName) {
      throw StateError('simulated database failure at /data/user/0/app/downloads/secret.mp3');
    }
    return super.into(table);
  }
}
