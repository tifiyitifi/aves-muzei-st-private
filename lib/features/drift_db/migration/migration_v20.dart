import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v19 -> v20: the gallery's group 0 becomes the 「Unrestricted」
/// sentinel.
///
/// Group 0 is the browsing state that narrows nothing; it must stay empty, so a
/// pre-release base or a condition saved into it would contradict it. This fork
/// has no released installs, so the gallery scope is reset instead of migrated:
/// the wallpaper pools belong to their groups and keep their filters, while the
/// gallery is re-seeded from the bundled defaults on the next start.
class MigrationV20 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    Future<bool> hasTable(String name) async {
      final rows = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", variables: [Variable.withString(name)]).get();
      return rows.isNotEmpty;
    }

    final hasRanges = await hasTable('visible_ranges');
    if (!hasRanges) return;

    if (await hasTable('visible_range_rules')) {
      await db.customStatement(
        "DELETE FROM visible_range_rules WHERE rangeId IN (SELECT id FROM visible_ranges WHERE scope = 'gallery')",
      );
    }
    if (await hasTable('visible_range_rule_usage')) {
      await db.customStatement(
        "DELETE FROM visible_range_rule_usage WHERE rangeId IN (SELECT id FROM visible_ranges WHERE scope = 'gallery')",
      );
    }
    await db.customStatement("DELETE FROM visible_ranges WHERE scope = 'gallery'");
    if (await hasTable('visible_range_state')) {
      // Dropping the defaults marker makes the seeder rebuild the built-in
      // groups and the outside pool on the next start.
      await db.customStatement(
        "DELETE FROM visible_range_state WHERE key IN ('gallery.current', 'gallery.rangeId', 'defaults.version', 'seeded')",
      );
    }
  }
}
