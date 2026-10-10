import 'package:drift/drift.dart';

class CoversTable extends Table {
  @override
  String get tableName => 'covers';

  TextColumn get filter => text()();
  IntColumn get entryId => integer().named('entryId').nullable()();
  TextColumn get packageName => text().named('packageName').nullable()();
  TextColumn get color => text().nullable()();

  @override
  Set<Column> get primaryKey => {filter};
}
