import 'package:drift/drift.dart';

/// Physical layout mirrors the legacy `metadata.db` v16 `entry` table.
///
/// Column names are pinned with `.named(...)` to the legacy camelCase names so
/// the one-time legacy import can copy rows verbatim and the existing
/// `AvesEntry.fromMap` / `toDatabaseMap` serializers keep working. Every column
/// except the primary key is nullable, matching the legacy schema.
class EntriesTable extends Table {
  @override
  String get tableName => 'entry';

  IntColumn get id => integer()();
  IntColumn get contentId => integer().named('contentId').nullable()();
  TextColumn get uri => text().nullable()();
  TextColumn get path => text().nullable()();
  TextColumn get sourceMimeType => text().named('sourceMimeType').nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get sourceRotationDegrees => integer().named('sourceRotationDegrees').nullable()();
  IntColumn get sizeBytes => integer().named('sizeBytes').nullable()();
  TextColumn get title => text().nullable()();
  IntColumn get dateAddedSecs => integer().named('dateAddedSecs').nullable()();
  IntColumn get dateModifiedMillis => integer().named('dateModifiedMillis').nullable()();
  IntColumn get sourceDateTakenMillis => integer().named('sourceDateTakenMillis').nullable()();
  IntColumn get durationMillis => integer().named('durationMillis').nullable()();
  IntColumn get trashed => integer().nullable()();
  IntColumn get origin => integer().nullable()();

  /// Raw single-level parent directory (`dirname(path)`), maintained by the
  /// entries domain on every write and backfilled by `MigrationV3`.
  ///
  /// Powers indexed album grouping and single-level directory filters without
  /// scanning paths. Display names still resolve through `entryDirRepo`, which
  /// may disambiguate case variants against the filesystem.
  TextColumn get directory => text().named('directory').nullable()();

  /// Raw `basenameWithoutExtension(path)`, maintained by the entries domain on
  /// every write and backfilled by `MigrationV4`.
  ///
  /// Gives the title search and the stack keys a SQL-visible file name: SQLite
  /// has no reverse `instr`, so neither the base name nor the extension can be
  /// derived from `path` inside a query.
  TextColumn get baseName => text().named('baseName').nullable()();

  /// Burst group key (`'<directory>/<burst key>'`), or NULL when no configured
  /// pattern matches the entry's name. Maintained on every write.
  TextColumn get stackKey => text().named('stackKey').nullable()();

  /// The row a stack member hides behind, or NULL when the row shows itself
  /// (the tile of its group, a row in no group, or a group with no single tile).
  ///
  /// Materialized because which member shows is a group-level decision (and, for
  /// bursts, needs a natural name order SQLite cannot express). The paged view
  /// hides a member only while its tile is in the same scope, so it tests
  /// `stackTileId IS NULL OR stackTileId IN (<tile ids the predicate admits>)`.
  IntColumn get stackTileId => integer().named('stackTileId').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
