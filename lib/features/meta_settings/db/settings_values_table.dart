import 'package:drift/drift.dart';

/// Sparse user overrides for the metadata settings engine (v2).
///
/// A row exists only for a key the user actually changed, so code-side defaults
/// keep reaching everyone who never customized a setting (matching the legacy
/// store's "only changed keys are persisted" behaviour).
///
/// Unlike the reference project's value table, this one also carries a `type`
/// tag: Aves persists dynamic, catalog-less keys (`tile_extent_*`, `widget_*`,
/// ...), so the typed [SettingsStore] getters cannot derive the type from a
/// `SettingDef`.
class SettingsValuesTable extends Table {
  @override
  String get tableName => 'settingsValues';

  TextColumn get key => text()();

  /// `SettingValueType` name (`bool` / `int` / `double` / `string` /
  /// `stringList`).
  TextColumn get type => text()();

  /// Codec-encoded value (see `MetaSettingsValueCodec`).
  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
