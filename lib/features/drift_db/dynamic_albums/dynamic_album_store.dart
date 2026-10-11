import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/dynamic_albums.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Owns the `dynamicAlbums` table (named saved filters).
class DynamicAlbumStore {
  static const _table = 'dynamicAlbums';

  final AppDatabase db;

  new(this.db);

  Future<int> clear() async {
    final count = await db.delete(db.dynamicAlbumsTable).go();
    _log.d('$runtimeType clear deleted $count rows');
    return count;
  }

  Future<Set<DynamicAlbumRow>> loadAll() async {
    final result = <DynamicAlbumRow>{};
    for (final row in await selectAllRows(db, _table)) {
      final album = DynamicAlbumRow.fromMap(row.data);
      if (album != null) {
        result.add(album);
      } else {
        _log.w('$runtimeType failed to deserialize dynamic album from row=${row.data}');
      }
    }
    return result;
  }

  Future<void> add(Set<DynamicAlbumRow> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batchInsertReplace(batch, db.dynamicAlbumsTable, row.toDbMap());
      }
    });
  }

  Future<void> remove(Set<String> names) async {
    if (names.isEmpty) return;
    await db.batch((batch) {
      for (final name in names) {
        batch.deleteWhere(db.dynamicAlbumsTable, (t) => t.name.equals(name));
      }
    });
  }
}
