import 'package:drift/drift.dart';

/// `dateTaken` and `metadata` are written together by
/// `CatalogStore.update`, so they live in one slice.
class DateTakenTable extends Table {
  @override
  String get tableName => 'dateTaken';

  IntColumn get id => integer()();
  IntColumn get dateMillis => integer().named('dateMillis').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class MetadataTable extends Table {
  @override
  String get tableName => 'metadata';

  IntColumn get id => integer()();
  TextColumn get mimeType => text().named('mimeType').nullable()();
  IntColumn get dateMillis => integer().named('dateMillis').nullable()();
  IntColumn get flags => integer().nullable()();
  IntColumn get rotationDegrees => integer().named('rotationDegrees').nullable()();
  TextColumn get xmpSubjects => text().named('xmpSubjects').nullable()();
  TextColumn get xmpTitle => text().named('xmpTitle').nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get rating => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
