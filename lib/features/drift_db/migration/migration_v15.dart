import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v14 -> v15: the fork's copy-first edit sessions.
///
/// Every edited photo gets a session row plus one output row per file it produced. Both tables are
/// new, so the migration only has to create them (and the session lookup index) on installs that
/// upgrade; fresh installs get them from `createAll`.
class MigrationV15 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('refra_edit_sessions', 'refra_edit_outputs')",
    ).get();
    final existing = tables.map((row) => row.data['name']).toSet();
    if (!existing.contains('refra_edit_sessions')) {
      await m.createTable(db.refraEditSessionRows);
    }
    if (!existing.contains('refra_edit_outputs')) {
      await m.createTable(db.refraEditOutputRows);
    }
    await createNewIndexes(db);
  }

  static Future<void> createNewIndexes(AppDatabase db) async {
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_refra_edit_sessions_created_at ON refra_edit_sessions (createdAt)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_refra_edit_outputs_session ON refra_edit_outputs (sessionId)',
    );
  }
}
