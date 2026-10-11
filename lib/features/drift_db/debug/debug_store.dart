import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Owns the `debug` table (platform debug log).
class DebugStore {
  static const _table = 'debug';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.debugTable).go();
    _log.d('$runtimeType clear deleted $count rows');
  }

  Future<List<String>> loadAll() async {
    return (await selectAllRows(db, _table)).map((row) => row.data['message'] as String).toList();
  }

  Future<void> add(String message) async {
    await insertReplace(db, db.debugTable, {'message': message});
  }
}
