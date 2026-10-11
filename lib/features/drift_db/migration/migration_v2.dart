import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';

/// Schema v1 -> v2: adds the metadata-settings value table.
class MigrationV2 {
  final AppDatabase db;

  new(this.db);

  Future<void> run(Migrator m) async {
    await m.createTable(db.settingsValuesTable);
  }
}
