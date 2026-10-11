import 'package:sqflite/sqflite.dart';

/// `sqflite`-only helper, retained together with the legacy database engine
/// (`db_sqflite*.dart`) for historical reference. Not used by the active Drift
/// backend.
extension ExtraDatabase on Database {
  // check table existence via `sqlite_master`
  // `sqlite_schema` is the alias used in SQLite documentation,
  // but it was introduced in SQLite v3.33.0 and it is unavailable on Android API < 34,
  // and the historical alias `sqlite_master` is still supported.
  // cf https://www.sqlite.org/faq.html#q7
  Future<bool> tableExists(String table) async {
    final results = await query('sqlite_master', where: 'type = ? AND name = ?', whereArgs: ['table', table]);
    return results.isNotEmpty;
  }
}
