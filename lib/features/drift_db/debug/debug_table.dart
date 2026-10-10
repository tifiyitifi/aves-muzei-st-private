import 'package:drift/drift.dart';

class DebugTable extends Table {
  @override
  String get tableName => 'debug';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get message => text().nullable()();
}
