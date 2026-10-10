import 'package:drift/drift.dart';

class VaultsTable extends Table {
  @override
  String get tableName => 'vaults';

  TextColumn get name => text()();
  IntColumn get autoLock => integer().named('autoLock').nullable()();
  IntColumn get useBin => integer().named('useBin').nullable()();
  TextColumn get lockType => text().named('lockType').nullable()();

  @override
  Set<Column> get primaryKey => {name};
}
