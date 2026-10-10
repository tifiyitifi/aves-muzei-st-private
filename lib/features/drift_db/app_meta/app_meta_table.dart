import 'package:drift/drift.dart';

/// Fork-only key/value bookkeeping, not a user setting.
///
/// Currently only the one-time legacy import flag lives here, so a partially
/// applied import can never look "done" after a crash.
class AppMetaTable extends Table {
  @override
  String get tableName => 'appMeta';

  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
