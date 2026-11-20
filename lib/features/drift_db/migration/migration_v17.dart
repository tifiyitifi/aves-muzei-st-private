import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v16 -> v17: batch results and saved batch profiles.
///
/// Batch processing never touches an original, so what it produced needs a
/// durable record: the results folder alone cannot say which source a copy came
/// from, and "replace the original" or "move it back" would otherwise be blind.
/// Profiles keep the action chain reusable across runs and, in the next step,
/// across copy-share.
class MigrationV17 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    await m.createTable(db.batchResultRows);
    await m.createTable(db.batchProfileRows);
    await createNewIndexes(db);
  }

  static Future<void> createNewIndexes(AppDatabase db) async {
    await db.customStatement('CREATE INDEX IF NOT EXISTS idx_batch_results_source_uri ON batch_results (sourceUri)');
    await db.customStatement('CREATE INDEX IF NOT EXISTS idx_batch_results_status ON batch_results (status)');
    await db.customStatement('CREATE INDEX IF NOT EXISTS idx_batch_results_created_at ON batch_results (createdAt)');
    await db.customStatement('CREATE INDEX IF NOT EXISTS idx_batch_profiles_kind ON batch_profiles (kind)');
  }
}
