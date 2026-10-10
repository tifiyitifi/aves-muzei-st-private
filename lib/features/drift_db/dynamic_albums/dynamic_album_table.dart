import 'package:drift/drift.dart';

class DynamicAlbumsTable extends Table {
  @override
  String get tableName => 'dynamicAlbums';

  TextColumn get name => text()();
  TextColumn get filter => text().nullable()();

  @override
  Set<Column> get primaryKey => {name};
}
