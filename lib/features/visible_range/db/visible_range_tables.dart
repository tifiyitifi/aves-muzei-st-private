import 'package:drift/drift.dart';

/// Catalog of reusable **base ranges**. "Unrestricted" is represented by an
/// empty base filter set and is never a row.
///
/// A base is a snapshot: selecting one copies its filters onto the owning
/// [VisibleRangeRows] row, so editing a preset never rewrites a range behind the
/// user's back.
class VisibleRangePresetRows extends Table {
  @override
  String get tableName => 'visible_range_presets';

  TextColumn get id => text()();

  TextColumn get name => text()();

  /// Free-form user note, e.g. when and from what the base was pinned.
  TextColumn get description => text().withDefault(const Constant(''))();

  /// JSON array of `CollectionFilter.toJsonMap()` bodies, AND-ed together.
  TextColumn get filters => text().withDefault(const Constant('[]'))();

  /// Built-in presets are read-only and re-addable through the "re-add default
  /// restrictions" action.
  BoolColumn get builtin => boolean().withDefault(const Constant(false))();

  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One visible range: a base plus its restriction/supplement rule sets.
///
/// `scope` is `gallery` (a single range, owner `gallery`) or `wallpaper`
/// (one range per wallpaper group, owner = group id). The two scopes are stored
/// side by side but never share a row, so the wallpaper engine can evolve
/// without moving gallery data.
class VisibleRangeRows extends Table {
  @override
  String get tableName => 'visible_ranges';

  TextColumn get id => text()();

  TextColumn get scope => text()();

  /// Owner of the range: `gallery` for the single gallery range, otherwise the
  /// wallpaper group id.
  TextColumn get ownerId => text().named('ownerId')();

  /// Display name of the selected base (empty when [baseFilters] is empty).
  TextColumn get baseName => text().named('baseName').withDefault(const Constant(''))();

  /// Preset this base was last copied from, or empty for unrestricted/custom.
  TextColumn get basePresetId => text().named('basePresetId').withDefault(const Constant(''))();

  /// JSON array, AND-ed together. Empty means unrestricted.
  TextColumn get baseFilters => text().named('baseFilters').withDefault(const Constant('[]'))();

  /// `intersectFirst` (restrictions before supplements) or `unionFirst`
  /// (supplements before restrictions).
  TextColumn get orderMode => text().named('orderMode').withDefault(const Constant('intersectFirst'))();

  BoolColumn get locked => boolean().withDefault(const Constant(false))();

  /// JSON of `VisibleRangePermissions`; null means the default (read-only with
  /// sharing allowed).
  TextColumn get permissions => text().nullable()();

  IntColumn get createdAt => integer().named('createdAt')();

  IntColumn get updatedAt => integer().named('updatedAt')();

  @override
  Set<Column> get primaryKey => {id};
}

/// One rule of a visible range. `kind` is `restriction` (AND) or `supplement`
/// (OR); a rule's own filters are AND-ed together.
class VisibleRangeRuleRows extends Table {
  @override
  String get tableName => 'visible_range_rules';

  TextColumn get id => text()();

  TextColumn get rangeId => text().named('rangeId')();

  TextColumn get kind => text()();

  IntColumn get position => integer().withDefault(const Constant(0))();

  TextColumn get label => text().withDefault(const Constant(''))();

  /// Free-form user note, e.g. when and from what the rule was pinned.
  TextColumn get description => text().withDefault(const Constant(''))();

  /// JSON array of filter bodies.
  TextColumn get filters => text().withDefault(const Constant('[]'))();

  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One "activate to media set" session, kept until the next save so the user can
/// write its delta back to the rule it came from.
class VisibleRangeSessionRows extends Table {
  @override
  String get tableName => 'visible_range_sessions';

  TextColumn get id => text()();

  TextColumn get rangeId => text().named('rangeId')();

  TextColumn get ruleId => text().named('ruleId')();

  TextColumn get kind => text()();

  /// `override` or `append`.
  TextColumn get mode => text()();

  /// JSON array of the media-set filters right after activation.
  TextColumn get initialFilters => text().named('initialFilters').withDefault(const Constant('[]'))();

  /// JSON array of the media-set filters when the session ended.
  TextColumn get finalFilters => text().named('finalFilters').withDefault(const Constant('[]'))();

  IntColumn get createdAt => integer().named('createdAt')();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key/value state owned by the visible-range feature: the current
/// gallery range id, temporary-unlock flags, the one-time seed marker.
class VisibleRangeKeyValues extends Table {
  @override
  String get tableName => 'visible_range_state';

  TextColumn get key => text()();

  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
