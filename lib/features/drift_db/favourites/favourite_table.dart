import 'package:drift/drift.dart';

class FavouritesTable extends Table {
  @override
  String get tableName => 'favourites';

  IntColumn get id => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
