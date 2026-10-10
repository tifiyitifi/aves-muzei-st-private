import 'package:drift/drift.dart';

class TrashTable extends Table {
  @override
  String get tableName => 'trash';

  IntColumn get id => integer()();
  TextColumn get path => text().nullable()();
  IntColumn get dateMillis => integer().named('dateMillis').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
