import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:flutter/foundation.dart';

/// Owns the `debug` table (platform debug log).
class DebugStore {
  static const _table = 'debug';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.debugTable).go();
    debugPrint('$runtimeType clear deleted $count rows');
  }

  Future<List<String>> loadAll() async {
    return (await selectAllRows(db, _table)).map((row) => row.data['message'] as String).toList();
  }

  Future<void> add(String message) async {
    await insertReplace(db, db.debugTable, {'message': message});
  }
}
