import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:drift/drift.dart';

/// Schema v2 -> v3: adds the indexed `entry.directory` column.
///
/// The column stores the raw `dirname(path)` for every row, so album grouping
/// and single-level directory filters become indexed `GROUP BY`/equality
/// operations instead of full path scans. `bestDate` ordering still computes
/// from the date columns (see `EntryStore.loadWindow`); only the directory
/// key is materialized, because it is the one grouping key SQLite cannot
/// derive with an index (no `reverse()` for `dirname`).
class MigrationV3 {
  final AppDatabase db;

  new(this.db);

  static const List<String> _indexes = [
    'CREATE INDEX IF NOT EXISTS idx_entry_origin_trashed ON entry(origin, trashed)',
    'CREATE INDEX IF NOT EXISTS idx_entry_directory ON entry(directory)',
    'CREATE INDEX IF NOT EXISTS idx_entry_sourceDateTaken ON entry(sourceDateTakenMillis)',
    'CREATE INDEX IF NOT EXISTS idx_dateTaken_dateMillis ON dateTaken(dateMillis)',
    'CREATE INDEX IF NOT EXISTS idx_metadata_rating ON metadata(rating)',
  ];

  /// Creates the v3 indexes on a fresh database (called from `onCreate`).
  static Future<void> createNewIndexes(AppDatabase db) async {
    for (final statement in _indexes) {
      await db.customStatement(statement);
    }
  }

  Future<void> run(Migrator m) async {
    await m.addColumn(db.entriesTable, db.entriesTable.directory);
    await _backfillDirectories();
    await createNewIndexes(db);
  }

  /// Fills `directory` for rows written before the column existed (legacy
  /// imports, pre-v3 writes), in bounded chunks so a million-row table does
  /// not materialize in memory mid-migration. Path-less rows legitimately keep
  /// a NULL directory and are excluded from the work query.
  Future<void> _backfillDirectories() async {
    const chunkSize = 500;
    while (true) {
      final rows = await db.customSelect('SELECT id, path FROM entry WHERE directory IS NULL AND path IS NOT NULL LIMIT $chunkSize').get();
      if (rows.isEmpty) return;
      await db.batch((batch) {
        for (final row in rows) {
          final data = row.data;
          batch.update(
            db.entriesTable,
            EntriesTableCompanion(directory: Value(EntryStore.directoryOf(data['path'] as String?))),
            where: (t) => t.id.equals(data['id'] as int),
          );
        }
      });
    }
  }
}
