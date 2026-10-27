import 'dart:convert';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_usage.dart';
import 'package:drift/drift.dart';

/// Persistence for visible ranges. Every read is scope+owner qualified, so the
/// gallery and the wallpaper groups can never leak into each other.
class VisibleRangeStore {
  /// Key of the persisted gallery range id (the gallery keeps one range).
  static const keyGalleryRangeId = 'gallery.rangeId';

  /// Key of the last permissions preset, reused by the quick lock.
  static const keyLastLockPreset = 'lock.preset';

  /// One-time seeding marker for the built-in presets.
  static const keySeeded = 'seeded';

  /// Version of the bundled defaults last written. A new version re-seeds the
  /// built-in base presets and materializes the built-in rules, so an upgraded
  /// install sees the same defaults as a fresh one.
  ///
  /// A bump has two intended side effects:
  /// - defaults the user deleted come back;
  /// - defaults removed from the bundle, and their activation state, are pruned.
  ///
  /// Both are deliberate trade-offs of keeping the bundle as the single source
  /// of truth: every install converges on one known-good set instead of drifting
  /// with pieces of older bundles. A per-item tombstone would let deletions
  /// survive, at the cost of a second source of truth. User-created rules and
  /// presets are never touched, and an active or renamed default keeps its state.
  static const keyDefaultsVersion = 'defaults.version';
  static const defaultsVersion = 3;

  /// Page view preferences, persisted with the range store so the feature does
  /// not add upstream settings keys.
  static const keyActiveStyle = 'view.activeStyle';

  final AppDatabase db;

  new(this.db);

  // ranges

  Future<VisibleRange?> loadRange({required VisibleRangeScope scope, required String ownerId}) async {
    final query = db.select(db.visibleRangeRows)..where((t) => t.scope.equals(scope.name) & t.ownerId.equals(ownerId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final rules = await loadRules(row.id);
    return _toRange(row, rules);
  }

  Future<void> saveRange(VisibleRange range) async {
    // A range and its rules are one aggregate: every caller reads them back
    // together, so a rule edit must be written with the range instead of
    // lingering in memory until the next explicit `replaceRules`.
    await db.transaction(() async {
      await db.visibleRangeRows.insertOnConflictUpdate(
        VisibleRangeRowsCompanion.insert(
          id: range.id,
          scope: range.scope.name,
          ownerId: range.ownerId,
          createdAt: range.createdAt,
          updatedAt: range.updatedAt,
          baseName: Value(range.baseName),
          basePresetId: Value(range.basePresetId),
          baseFilters: Value(VisibleRangeFilterCodec.encode(range.baseFilters)),
          orderMode: Value(range.order.name),
          locked: Value(range.locked),
          permissions: Value(range.locked ? _encodePermissions(range.permissions) : null),
        ),
      );
      await (db.delete(db.visibleRangeRuleRows)..where((t) => t.rangeId.equals(range.id))).go();
      for (final rule in range.rules) {
        await saveRule(rule);
      }
      // A rule that no longer exists cannot be written back: drop the targets
      // that pointed at the removed rules. The base target belongs to the range
      // itself, so it stays.
      final keptRuleIds = {for (final rule in range.rules) rule.id};
      final usageRows = await (db.select(db.visibleRangeRuleUsageRows)..where((t) => t.rangeId.equals(range.id))).get();
      final stale = [
        for (final row in usageRows)
          if (!row.id.startsWith('base.') && !keptRuleIds.contains(row.targetId)) row.id,
      ];
      if (stale.isNotEmpty) {
        await (db.delete(db.visibleRangeRuleUsageRows)..where((t) => t.id.isIn(stale))).go();
      }
    });
  }

  Future<void> replaceRules(String rangeId, List<VisibleRangeRule> rules) async {
    await db.transaction(() async {
      await (db.delete(db.visibleRangeRuleRows)..where((t) => t.rangeId.equals(rangeId))).go();
      for (final rule in rules) {
        await saveRule(rule);
      }
    });
  }

  Future<void> deleteRange(String id) async {
    await db.transaction(() async {
      await (db.delete(db.visibleRangeRuleRows)..where((t) => t.rangeId.equals(id))).go();
      await (db.delete(db.visibleRangeRuleUsageRows)..where((t) => t.rangeId.equals(id))).go();
      await (db.delete(db.visibleRangeRows)..where((t) => t.id.equals(id))).go();
    });
  }

  // rules

  Future<List<VisibleRangeRule>> loadRules(String rangeId) async {
    final query = db.select(db.visibleRangeRuleRows)
      ..where((t) => t.rangeId.equals(rangeId))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    final rows = await query.get();
    return [for (final row in rows) _toRule(row)];
  }

  Future<void> saveRule(VisibleRangeRule rule) async {
    await db.visibleRangeRuleRows.insertOnConflictUpdate(
      VisibleRangeRuleRowsCompanion.insert(
        id: rule.id,
        rangeId: rule.rangeId,
        kind: rule.kind.name,
        position: Value(rule.position),
        label: Value(rule.label),
        description: Value(rule.description),
        filters: Value(VisibleRangeFilterCodec.encode(rule.filters)),
        active: Value(rule.active),
      ),
    );
  }

  Future<void> deleteRules(Set<String> ids) async {
    if (ids.isEmpty) return;
    await (db.delete(db.visibleRangeRuleRows)..where((t) => t.id.isIn(ids))).go();
  }

  // presets

  Future<List<VisibleRangePreset>> loadPresets() async {
    final query = db.select(db.visibleRangePresetRows)..orderBy([(t) => OrderingTerm.asc(t.position)]);
    final rows = await query.get();
    return [for (final row in rows) _toPreset(row)];
  }

  Future<void> savePreset(VisibleRangePreset preset) async {
    await db.visibleRangePresetRows.insertOnConflictUpdate(
      VisibleRangePresetRowsCompanion.insert(
        id: preset.id,
        name: preset.name,
        description: Value(preset.description),
        filters: Value(VisibleRangeFilterCodec.encode(preset.filters)),
        builtin: Value(preset.builtin),
        position: Value(preset.position),
      ),
    );
  }

  Future<void> deletePreset(String id) async {
    await (db.delete(db.visibleRangePresetRows)..where((t) => t.id.equals(id))).go();
  }

  /// Drops every built-in preset, keeping the user's own saves. Used when the
  /// bundled defaults change, so removed entries disappear instead of lingering
  /// as unlabelled leftovers.
  Future<void> deleteBuiltinPresets() async {
    await (db.delete(db.visibleRangePresetRows)..where((t) => t.builtin.equals(true))).go();
  }

  /// Drops the built-in presets missing from the current bundle, keeping the
  /// user's own saves and the built-ins still shipped.
  ///
  /// The seeding pass re-saves the kept built-ins with their bundled position,
  /// so this only removes stale entries after a defaults bump.
  Future<void> deleteBuiltinPresetsExcept(Set<String> keepIds) async {
    if (keepIds.isEmpty) return deleteBuiltinPresets();
    await (db.delete(db.visibleRangePresetRows)..where((t) => t.builtin.equals(true) & t.id.isNotIn(keepIds))).go();
  }

  // state

  Future<String?> readState(String key) async {
    final query = db.select(db.visibleRangeKeyValues)..where((t) => t.key.equals(key));
    return (await query.getSingleOrNull())?.value;
  }

  Future<void> writeState(String key, String? value) async {
    await db.visibleRangeKeyValues.insertOnConflictUpdate(
      VisibleRangeKeyValuesCompanion.insert(key: key, value: Value(value)),
    );
  }

  // usage

  /// Every remembered target, most recently used first.
  Future<List<VisibleRangeRuleUsage>> loadUsages() async {
    final query = db.select(db.visibleRangeRuleUsageRows)..orderBy([(t) => OrderingTerm.desc(t.usedAt)]);
    final rows = await query.get();
    return [for (final row in rows) _toUsage(row)];
  }

  Future<void> saveUsage(VisibleRangeRuleUsage usage) async {
    await db.visibleRangeRuleUsageRows.insertOnConflictUpdate(
      VisibleRangeRuleUsageRowsCompanion.insert(
        id: usage.id,
        rangeId: usage.rangeId,
        targetId: Value(usage.targetId),
        kind: usage.kind.name,
        usedAt: usage.usedAt,
      ),
    );
  }

  Future<void> deleteUsages(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (db.delete(db.visibleRangeRuleUsageRows)..where((t) => t.id.isIn(list))).go();
  }

  // mapping

  static VisibleRange _toRange(VisibleRangeRow row, List<VisibleRangeRule> rules) {
    return VisibleRange(
      id: row.id,
      scope: VisibleRangeScope.parse(row.scope),
      ownerId: row.ownerId,
      baseName: row.baseName,
      basePresetId: row.basePresetId,
      baseFilters: VisibleRangeFilterCodec.decode(row.baseFilters),
      rules: rules,
      order: VisibleRangeOrder.parse(row.orderMode),
      locked: row.locked,
      permissions: _decodePermissions(row.permissions),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  static VisibleRangeRule _toRule(VisibleRangeRuleRow row) => VisibleRangeRule(
        id: row.id,
        rangeId: row.rangeId,
        kind: VisibleRangeRuleKind.parse(row.kind),
        position: row.position,
        label: row.label,
        description: row.description,
        filters: VisibleRangeFilterCodec.decode(row.filters),
        active: row.active,
      );

  static VisibleRangePreset _toPreset(VisibleRangePresetRow row) => VisibleRangePreset(
        id: row.id,
        name: row.name,
        description: row.description,
        filters: VisibleRangeFilterCodec.decode(row.filters),
        builtin: row.builtin,
        position: row.position,
      );

  static VisibleRangeRuleUsage _toUsage(VisibleRangeRuleUsageRow row) => VisibleRangeRuleUsage(
        id: row.id,
        rangeId: row.rangeId,
        targetId: row.targetId,
        kind: VisibleRangeCandidateKind.values.firstWhere((v) => v.name == row.kind, orElse: () => VisibleRangeCandidateKind.restriction),
        usedAt: row.usedAt,
      );

  static String _encodePermissions(VisibleRangePermissions permissions) => jsonEncode(permissions.toMap());

  static VisibleRangePermissions _decodePermissions(String? raw) {
    if (raw == null || raw.isEmpty) return VisibleRangePermissions.readOnly;
    try {
      return VisibleRangePermissions.fromMap(jsonDecode(raw)) ?? VisibleRangePermissions.readOnly;
    } catch (_) {
      return VisibleRangePermissions.readOnly;
    }
  }
}
