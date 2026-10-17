import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:aves/features/stacking/model/stack_grouping.dart';
import 'package:drift/drift.dart';

/// Schema v3 -> v4: adds the stack index columns to `entry`.
///
/// `baseName` is the file name without its extension, which SQLite cannot derive
/// from `path` (no reverse `instr`); `stackKey` is the burst group key; and
/// `stackTileId` points the members of a stack at the row that shows, so the
/// paged view hides them without a per-row group lookup.
class MigrationV4 {
  final AppDatabase db;

  new(this.db);

  static const List<String> _indexes = [
    'CREATE INDEX IF NOT EXISTS idx_entry_stackKey ON entry(stackKey)',
    'CREATE INDEX IF NOT EXISTS idx_entry_directory_baseName ON entry(directory, baseName)',
    // The tile id is mostly NULL; the index is what makes both the "does this
    // library have stacks" probe and the member lookup cheap.
    'CREATE INDEX IF NOT EXISTS idx_entry_stackTileId ON entry(stackTileId)',
  ];

  /// Creates the v4 indexes on a fresh database (called from `onCreate`).
  static Future<void> createNewIndexes(AppDatabase db) async {
    for (final statement in _indexes) {
      await db.customStatement(statement);
    }
  }

  Future<void> run(Migrator m) async {
    await m.addColumn(db.entriesTable, db.entriesTable.baseName);
    await m.addColumn(db.entriesTable, db.entriesTable.stackKey);
    await m.addColumn(db.entriesTable, db.entriesTable.stackTileId);
    await _backfillNames();
    // A tile is a group-level decision, so the whole table has to be settled
    // once.
    await EntryStore(db).reindexAllStacks();
    await createNewIndexes(db);
  }

  /// Fills `baseName` and `stackKey` for rows written before the columns existed
  /// (legacy imports, pre-v4 writes), in bounded chunks so a million-row table
  /// does not materialize in memory mid-migration. Path-less rows legitimately
  /// keep both empty and are excluded from the work query.
  Future<void> _backfillNames() async {
    final store = EntryStore(db);
    const chunkSize = 500;
    while (true) {
      final rows = await db.customSelect('SELECT id, path FROM entry WHERE baseName IS NULL AND path IS NOT NULL LIMIT $chunkSize').get();
      if (rows.isEmpty) return;
      await db.batch((batch) {
        for (final row in rows) {
          final path = row.data['path'] as String;
          final directory = EntryStore.directoryOf(path);
          final baseName = StackGrouping.baseNameOf(path);
          batch.update(
            db.entriesTable,
            EntriesTableCompanion(
              baseName: Value(baseName),
              stackKey: Value(StackGrouping.stackKeyOf(directory: directory, baseName: baseName, patterns: store.burstPatterns)),
            ),
            where: (t) => t.id.equals(row.data['id'] as int),
          );
        }
      });
    }
  }
}
