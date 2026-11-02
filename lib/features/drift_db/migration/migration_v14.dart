import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

/// One rule of the pool while the merge is in progress.
typedef _PoolRule = ({
  String id,
  VisibleRangeRuleKind kind,
  int position,
  String label,
  String description,
  String filters,
  int surfaces,
});

/// Schema v13 -> v14: a wallpaper group stores its conditions once.
///
/// Home and lock stop owning a range each. The group keeps a single `wallpaper`
/// range row — its condition pool — and every base/rule carries a bit mask of the
/// surfaces that use it. The projection the engine consumes is rebuilt from the
/// pool (see `projectWallpaperGroupRange`), so `state.json` keeps the historical
/// per-surface range ids.
///
/// The old lock range row is folded into the pool:
/// - identical rules merge into one row marked for both surfaces;
/// - a lock-only rule moves into the pool row marked for the lock surface;
/// - an identical base is marked for both;
/// - a *different* lock base becomes a lock-only restriction, which is
///   arithmetically the same range: an unrestricted base offers everything, so
///   AND-ing the old base filters narrows it exactly as the base did.
class MigrationV14 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    await _addColumn('visible_ranges', 'baseSurfaces', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumn('visible_range_rules', 'surfaces', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumn('wallpaper_groups', 'lockRangeSeeded', 'INTEGER NOT NULL DEFAULT 0');
    if (!await _tableExists('visible_ranges') || !await _tableExists('visible_range_rules')) return;
    await _foldLockRanges();
  }

  Future<bool> _tableExists(String table) async {
    final rows = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", variables: [Variable.withString(table)]).get();
    return rows.isNotEmpty;
  }

  Future<void> _addColumn(String table, String column, String definition) async {
    if (!await _tableExists(table)) return;
    // A database that upgraded through an earlier version already has the column
    // with the current shape, so the alter is skipped when it exists.
    final columns = await db.customSelect('PRAGMA table_info($table)').get();
    if (columns.any((row) => row.data['name'] == column)) return;
    await db.customStatement('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// Merges every wallpaper group's lock range into its home (pool) row.
  Future<void> _foldLockRanges() async {
    final rangeRows = await db.customSelect("SELECT * FROM visible_ranges WHERE scope = 'wallpaper'").get();
    if (rangeRows.isEmpty) return;
    final ruleRows = await db.customSelect('SELECT * FROM visible_range_rules').get();
    final rulesByRange = <String, List<QueryRow>>{};
    for (final row in ruleRows) {
      (rulesByRange[row.data['rangeId'] as String] ??= []).add(row);
    }
    final usageRows = await _tableExists('visible_range_rule_usage') ? await db.customSelect('SELECT * FROM visible_range_rule_usage').get() : const <QueryRow>[];
    final hasLockSeeded = (await db.customSelect('PRAGMA table_info(wallpaper_groups)').get()).any((row) => row.data['name'] == 'lockRangeSeeded');

    final homeRows = <String, QueryRow>{};
    final lockRows = <String, QueryRow>{};
    for (final row in rangeRows) {
      final id = row.data['id'] as String;
      if (id.endsWith('.lock.range')) {
        lockRows[id.substring(0, id.length - '.lock.range'.length)] = row;
      } else {
        homeRows[row.data['ownerId'] as String] = row;
      }
    }

    for (final entry in homeRows.entries) {
      final groupId = entry.key;
      final home = entry.value;
      final homeId = home.data['id'] as String;
      final lock = lockRows[groupId];
      final homeBaseFilters = VisibleRangeFilterCodec.decode(home.data['baseFilters']);
      final homeBaseActive = _bool(home.data['baseActive']);
      var baseSurfaces = homeBaseActive && homeBaseFilters.isNotEmpty ? WallpaperConditionSurfaces.home : 0;

      final pool = <_PoolRule>[];
      for (final row in rulesByRange[homeId] ?? const <QueryRow>[]) {
        pool.add((
          id: row.data['id'] as String,
          kind: VisibleRangeRuleKind.parse(row.data['kind'] as String?),
          position: row.data['position'] as int? ?? 0,
          label: row.data['label'] as String? ?? '',
          description: row.data['description'] as String? ?? '',
          filters: row.data['filters'] as String? ?? '[]',
          surfaces: _bool(row.data['active']) ? WallpaperConditionSurfaces.home : 0,
        ));
      }

      if (lock != null) {
        final lockId = lock.data['id'] as String;
        final lockBaseFilters = VisibleRangeFilterCodec.decode(lock.data['baseFilters']);
        final lockBaseActive = _bool(lock.data['baseActive']);
        if (lockBaseActive && lockBaseFilters.isNotEmpty) {
          final sameBase = filterFingerprint(lockBaseFilters) == filterFingerprint(homeBaseFilters) && (lock.data['baseName'] as String? ?? '') == (home.data['baseName'] as String? ?? '');
          if (homeBaseFilters.isEmpty) {
            // The home surface has no base at all: the lock base becomes the pool's.
            await db.customUpdate(
              'UPDATE visible_ranges SET baseName = ?, basePresetId = ?, baseFilters = ?, baseActive = 1 WHERE id = ?',
              variables: [
                Variable.withString(lock.data['baseName'] as String? ?? ''),
                Variable.withString(lock.data['basePresetId'] as String? ?? ''),
                Variable.withString(lock.data['baseFilters'] as String? ?? '[]'),
                Variable.withString(homeId),
              ],
            );
            baseSurfaces = WallpaperConditionSurfaces.lock;
          } else if (sameBase) {
            baseSurfaces |= WallpaperConditionSurfaces.lock;
          } else {
            // Keep the lock base's narrowing as a lock-only restriction: with an
            // unrestricted base, AND-ing those filters is the same range.
            final id = 'migrated.$groupId.lockbase';
            pool.add((
              id: id,
              kind: VisibleRangeRuleKind.restriction,
              position: pool.where((rule) => rule.kind == VisibleRangeRuleKind.restriction).length,
              label: lock.data['baseName'] as String? ?? '',
              description: '',
              filters: lock.data['baseFilters'] as String? ?? '[]',
              surfaces: WallpaperConditionSurfaces.lock,
            ));
          }
        }

        for (final row in rulesByRange[lockId] ?? const <QueryRow>[]) {
          final lockRuleId = row.data['id'] as String;
          final lockRuleActive = _bool(row.data['active']);
          final fingerprint = filterFingerprint(VisibleRangeFilterCodec.decode(row.data['filters']));
          final kind = VisibleRangeRuleKind.parse(row.data['kind'] as String?);
          final pair = pool.where((rule) => rule.kind == kind && filterFingerprint(VisibleRangeFilterCodec.decode(rule.filters)) == fingerprint).firstOrNull;
          if (pair == null) {
            pool.add((
              id: lockRuleId,
              kind: kind,
              position: row.data['position'] as int? ?? 0,
              label: row.data['label'] as String? ?? '',
              description: row.data['description'] as String? ?? '',
              filters: row.data['filters'] as String? ?? '[]',
              surfaces: lockRuleActive ? WallpaperConditionSurfaces.lock : 0,
            ));
            continue;
          }
          final index = pool.indexWhere((rule) => rule.id == pair.id);
          pool[index] = (
            id: pair.id,
            kind: pair.kind,
            position: pair.position,
            label: pair.label,
            description: pair.description,
            filters: pair.filters,
            surfaces: pair.surfaces | (lockRuleActive ? WallpaperConditionSurfaces.lock : 0),
          );
        }
      }

      await db.customUpdate('UPDATE visible_ranges SET baseActive = 1, baseSurfaces = ? WHERE id = ?', variables: [Variable.withInt(baseSurfaces), Variable.withString(homeId)]);
      for (final rule in pool) {
        // The row may already exist (a home rule, or a lock rule moving into the
        // pool): update it first, and only insert a genuinely new condition (the
        // migrated lock base).
        final updated = await db.customUpdate(
          'UPDATE visible_range_rules SET rangeId = ?, kind = ?, position = ?, label = ?, description = ?, filters = ?, active = 1, surfaces = ? WHERE id = ?',
          variables: [
            Variable.withString(homeId),
            Variable.withString(rule.kind.name),
            Variable.withInt(rule.position),
            Variable.withString(rule.label),
            Variable.withString(rule.description),
            Variable.withString(rule.filters),
            Variable.withInt(rule.surfaces),
            Variable.withString(rule.id),
          ],
        );
        if (updated > 0) continue;
        await db.customStatement(
          'INSERT INTO visible_range_rules (id, rangeId, kind, position, label, description, filters, active, surfaces) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)',
          [rule.id, homeId, rule.kind.name, rule.position, rule.label, rule.description, rule.filters, rule.surfaces],
        );
      }

      if (lock == null) continue;
      final lockId = lock.data['id'] as String;
      final keptRuleIds = {for (final rule in pool) rule.id};
      for (final row in usageRows.where((row) => row.data['rangeId'] == lockId)) {
        final targetId = row.data['targetId'] as String? ?? '';
        if (targetId.isNotEmpty && !keptRuleIds.contains(targetId)) {
          await db.customStatement('DELETE FROM visible_range_rule_usage WHERE id = ?', [row.data['id'] as String]);
          continue;
        }
        final usageId = targetId.isEmpty ? 'base.$homeId' : 'rule.$targetId';
        await db.customStatement('UPDATE visible_range_rule_usage SET id = ?, rangeId = ? WHERE id = ?', [usageId, homeId, row.data['id'] as String]);
      }
      await db.customStatement('DELETE FROM visible_range_rules WHERE rangeId = ?', [lockId]);
      await db.customStatement('DELETE FROM visible_ranges WHERE id = ?', [lockId]);
      if (hasLockSeeded) await db.customStatement('UPDATE wallpaper_groups SET lockRangeSeeded = 1 WHERE id = ?', [groupId]);
    }
  }

  static bool _bool(Object? value) => value == true || value == 1;
}
