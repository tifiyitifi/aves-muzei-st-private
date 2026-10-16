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

  @override
  Set<Column> get primaryKey => {id};
}
