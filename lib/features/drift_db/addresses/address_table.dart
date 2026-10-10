import 'package:drift/drift.dart';

class AddressesTable extends Table {
  @override
  String get tableName => 'address';

  IntColumn get id => integer()();
  TextColumn get addressLine => text().named('addressLine').nullable()();
  TextColumn get countryCode => text().named('countryCode').nullable()();
  TextColumn get countryName => text().named('countryName').nullable()();
  TextColumn get adminArea => text().named('adminArea').nullable()();
  TextColumn get locality => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
