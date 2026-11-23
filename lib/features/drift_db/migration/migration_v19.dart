import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v18 -> v19: unify the gallery scenarios and the wallpaper groups.
///
/// A range used to be one base plus rules. It is now a **visibility group**: the
/// base becomes a `source` rule, and the gallery's old scope-wide restrictions
/// and supplements move to a shared `outside` row so switching groups keeps
/// them, exactly as before. The old base columns stay in place (one release) so
/// a rollback can still read the previous shape.
///
/// The gallery also becomes multi-group. Every saved preset materializes a group
/// with one source condition — the same mutually exclusive scenario set the old
/// page offered — and the group the old base pointed at becomes the current one.
///
/// Ids of wallpaper ranges are never touched: the engine, `state.json`, history
/// and the decoy range all address them.
class MigrationV19 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'visible_ranges'").get();
    if (tables.isEmpty) return; // A chain from before the feature: onCreate builds it.

    await _addColumnIfMissing('kind', "TEXT NOT NULL DEFAULT 'group'");
    await _addColumnIfMissing('name', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing('position', 'INTEGER NOT NULL DEFAULT 0');

    final now = DateTime.now().millisecondsSinceEpoch;

    // Every pre-refactor row is a group; the outside pool is a new row.
    await db.customStatement("UPDATE visible_ranges SET kind = 'group' WHERE kind IS NULL OR kind = '' OR kind = 'group'");

    // A chain from an intermediate version may predate one of the legacy
    // columns; read them only when they exist.
    final columns = {for (final row in await db.customSelect('PRAGMA table_info(visible_ranges)').get()) row.read<String>('name')};
    String legacy(String name, String fallback) => columns.contains(name) ? 'r.$name' : fallback;
    // The outside pool and the base collapse need the shape v18 shipped. An old
    // synthetic chain (a migration test) keeps its rows untouched, and the
    // controller's seeder creates the outside pool on the next start.
    final legacyReady = ['baseName', 'basePresetId', 'baseFilters', 'baseActive', 'baseSurfaces', 'orderMode', 'locked', 'permissions'].every(columns.contains);

    final ruleTable = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'visible_range_rules'").get();
    final usageTable = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'visible_range_rule_usage'").get();

    if (legacyReady) {
      await db.customStatement(
        'INSERT OR IGNORE INTO visible_ranges '
        '(id, scope, ownerId, kind, name, position, baseName, basePresetId, baseFilters, baseActive, baseSurfaces, orderMode, locked, permissions, createdAt, updatedAt) '
        "VALUES ('gallery.outside', 'gallery', 'gallery.outside', 'outside', '', 9999, '', '', '[]', 1, 0, 'intersectFirst', 0, NULL, $now, $now)",
      );

      // Old gallery restrictions/supplements were global: they belong to the
      // shared outside pool now, so they survive a group switch.
      if (ruleTable.isNotEmpty) {
        await db.customStatement(
          "UPDATE visible_range_rules SET rangeId = 'gallery.outside' WHERE rangeId = 'gallery' AND kind IN ('restriction', 'supplement')",
        );
      }
      if (usageTable.isNotEmpty) {
        await db.customStatement(
          "UPDATE visible_range_rule_usage SET rangeId = 'gallery.outside' WHERE rangeId = 'gallery' AND kind IN ('restriction', 'supplement')",
        );
      }
    }
    await db.customStatement('CREATE TABLE IF NOT EXISTS visible_range_state (key TEXT NOT NULL PRIMARY KEY, value TEXT)');

    final presetTables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'visible_range_presets'").get();
    final presetColumns = presetTables.isEmpty ? <String>{} : {for (final row in await db.customSelect('PRAGMA table_info(visible_range_presets)').get()) row.read<String>('name')};
    final presetsUsable = {'id', 'name', 'filters', 'builtin', 'position'}.every(presetColumns.contains);

    // A preset-backed gallery base is represented by the preset's own group
    // below; migrating it here too would duplicate the same source.
    final skipPresetBacked = columns.contains('basePresetId') && presetsUsable
        ? "AND NOT (r.id = 'gallery' AND r.basePresetId <> '' "
              'AND EXISTS (SELECT 1 FROM visible_range_presets p WHERE p.id = r.basePresetId))'
        : '';
    final bases = await db.customSelect(
      'SELECT r.id, ${legacy('baseName', "''")} AS baseName, ${legacy('baseFilters', "'[]'")} AS baseFilters, '
      "${legacy('baseActive', '1')} AS baseActive, ${legacy('baseSurfaces', '0')} AS baseSurfaces "
      'FROM visible_ranges r '
      "WHERE ${legacy('baseFilters', "'[]'")} <> '[]' AND ${legacy('baseFilters', "'[]'")} <> '' $skipPresetBacked",
    ).get();
    if (legacyReady && ruleTable.isNotEmpty) {
      for (final row in bases) {
        final id = row.read<String>('id');
        await db.customStatement(
          'INSERT OR IGNORE INTO visible_range_rules '
          '(id, rangeId, kind, position, label, description, filters, active, surfaces) '
          "VALUES (?, ?, 'source', 0, ?, '', ?, ?, ?)",
          [sourceRuleIdFor(id), id, row.read<String>('baseName'), row.read<String>('baseFilters'), row.read<int>('baseActive'), row.read<int>('baseSurfaces')],
        );
      }
    }

    // Presets become gallery groups (the old mutually exclusive scenarios).
    if (legacyReady && presetsUsable && ruleTable.isNotEmpty) {
      final description = presetColumns.contains('description') ? 'description' : "''";
      final presets = await db.customSelect('SELECT id, name, $description AS description, filters, builtin, position FROM visible_range_presets ORDER BY position').get();
      for (final row in presets) {
        final presetId = row.read<String>('id');
        final builtin = row.read<int>('builtin') != 0;
        final groupId = builtin ? 'builtin.group.$presetId' : 'preset.$presetId';
        await db.customStatement(
          'INSERT OR IGNORE INTO visible_ranges '
          '(id, scope, ownerId, kind, name, position, baseName, basePresetId, baseFilters, baseActive, baseSurfaces, orderMode, locked, permissions, createdAt, updatedAt) '
          "VALUES (?, 'gallery', ?, 'group', ?, ?, '', '', '[]', 1, 0, 'intersectFirst', 0, NULL, ?, ?)",
          [groupId, groupId, row.read<String>('name'), row.read<int>('position') + 1, now, now],
        );
        await db.customStatement(
          'INSERT OR IGNORE INTO visible_range_rules '
          '(id, rangeId, kind, position, label, description, filters, active, surfaces) '
          "VALUES (?, ?, 'source', 0, '', ?, ?, 1, 0)",
          [sourceRuleIdFor(groupId), groupId, row.read<String>('description'), row.read<String>('filters')],
        );
      }
    }

    // The old active base decides which group browsing starts on.
    var current = 'gallery';
    if (columns.contains('basePresetId')) {
      final gallery = await db.customSelect("SELECT basePresetId FROM visible_ranges WHERE id = 'gallery'").getSingleOrNull();
      final presetId = gallery?.read<String>('basePresetId') ?? '';
      if (presetId.isNotEmpty && presetsUsable) {
        final preset = await db.customSelect('SELECT builtin FROM visible_range_presets WHERE id = ?', variables: [Variable.withString(presetId)]).getSingleOrNull();
        if (preset != null) {
          current = preset.read<int>('builtin') != 0 ? 'builtin.group.$presetId' : 'preset.$presetId';
        }
      }
    }
    await db.customStatement("INSERT OR REPLACE INTO visible_range_state (key, value) VALUES ('gallery.current', ?)", [current]);
  }

  /// Rule id of the source condition a base migrates to.
  static String sourceRuleIdFor(String rangeId) => 'source.$rangeId';

  Future<void> _addColumnIfMissing(String column, String definition) async {
    final columns = await db.customSelect('PRAGMA table_info(visible_ranges)').get();
    if (columns.any((row) => row.read<String>('name') == column)) return;
    await db.customStatement('ALTER TABLE visible_ranges ADD COLUMN $column $definition');
  }
}
