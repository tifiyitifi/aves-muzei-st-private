import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/migration/migration_v16.dart';
import 'package:drift/drift.dart';

/// Schema v17 -> v18: make the media-store identity collection-aware.
///
/// V16 deduplicated on the bare `contentId`. MediaStore numbers its image and
/// video collections independently, so an image and a video can carry the same
/// number; the old index merged and deleted one of them, and every later import
/// of the missing file was silently ignored. The replacement key adds the mime
/// type, which distinguishes the collections while still collapsing the volume
/// aliases of one file (they share both values).
class MigrationV18 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    // A database from a test chain may carry only the tables its version needs:
    // there is no entry table to reindex then. DROP IF EXISTS keeps the
    // migration idempotent and safe to retry.
    await db.customStatement('DROP INDEX IF EXISTS idx_entry_media_store_content_id');
    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'entry'").get();
    if (tables.isEmpty) return;
    await createNewIndexes(db);
  }

  static Future<void> createNewIndexes(AppDatabase db) async => MigrationV16.createNewIndexes(db);
}
