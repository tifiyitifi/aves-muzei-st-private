import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Owns the `entry` table: CRUD, directory/origin loading, live search and
/// duplicate detection. Drift types never leave this store.
class EntryStore {
  static const _table = 'entry';
  static const _insertSliceMaxCount = 10000; // number of entries

  final AppDatabase db;

  new(this.db);

  Future<int> maxId() async {
    final rows = await db.customSelect('SELECT MAX(id) AS maxId FROM $_table').get();
    return (rows.firstOrNull?.data['maxId'] as int?) ?? 0;
  }

  Future<void> clear() async {
    final count = await db.delete(db.entriesTable).go();
    _log.d('$runtimeType clear deleted $count rows');
  }

  Future<Set<AvesEntry>> load({int? origin, String? directory}) async {
    final variables = <Variable>[];
    var where = '';
    if (origin != null) {
      where = 'origin = ?';
      variables.add(Variable(origin));
    }

    final entries = <AvesEntry>{};
    if (directory != null) {
      final separator = pContext.separator;
      if (!directory.endsWith(separator)) {
        directory = '$directory$separator';
      }

      where = '${where.isNotEmpty ? '$where AND ' : ''}path LIKE ?';
      variables.add(Variable('$directory%'));
      final rows = await db.customSelect('SELECT * FROM $_table WHERE $where', variables: variables).get();

      final dirLength = directory.length;
      for (final row in rows) {
        // skip entries in subfolders
        final path = row.data['path'] as String?;
        if (path != null && !path.substring(dirLength).contains(separator)) {
          entries.add(AvesEntry.fromMap(row.data));
        }
      }
    } else {
      final rows = where.isNotEmpty ? await db.customSelect('SELECT * FROM $_table WHERE $where', variables: variables).get() : await selectAllRows(db, _table);
      for (final row in rows) {
        entries.add(AvesEntry.fromMap(row.data));
      }
    }

    return entries;
  }

  Future<Set<AvesEntry>> loadByIds(Set<int> ids) => selectByIds(db, _table, ids, AvesEntry.fromMap);

  Future<void> insertAll(Set<AvesEntry> entries) async {
    if (entries.isEmpty) return;
    final stopwatch = Stopwatch()..start();
    var inserted = 0;
    // slice entries to avoid memory issues
    for (final slice in entries.slices(_insertSliceMaxCount)) {
      _log.d('$runtimeType inserting slice of [${inserted + 1}, ${inserted + slice.length}] entries');
      await db.batch((batch) {
        for (final entry in slice) {
          batchInsertReplace(batch, db.entriesTable, entry.toDatabaseMap());
        }
      });
      inserted += slice.length;
    }
    _log.d('$runtimeType insert complete in ${stopwatch.elapsed.inMilliseconds}ms for ${entries.length} entries');
  }

  Future<void> update(int id, AvesEntry entry) async {
    await db.batch((batch) {
      batch.deleteWhere(db.entriesTable, (t) => t.id.equals(id));
      batchInsertReplace(batch, db.entriesTable, entry.toDatabaseMap());
    });
  }

  Future<Set<AvesEntry>> searchLive(String query, {int? limit}) async {
    final variables = <Variable>[Variable('%$query%'), Variable('%$query%'), const Variable(0)];
    final limitClause = limit != null ? ' LIMIT ?' : '';
    if (limit != null) variables.add(Variable(limit));
    final rows = await db.customSelect(
      'SELECT * FROM $_table WHERE (title LIKE ? OR path LIKE ?) AND trashed = ? ORDER BY sourceDateTakenMillis DESC$limitClause',
      variables: variables,
    ).get();
    return rows.map((row) => AvesEntry.fromMap(row.data)).toSet();
  }

  Future<Set<AvesEntry>> searchDuplicates(int origin, Set<AvesEntry>? entries) async {
    var where = 'origin = ? AND trashed = ?';
    final variables = <Variable>[Variable(origin), const Variable(0)];
    if (entries != null) {
      where += ' AND contentId IN (${entries.map((v) => v.contentId).join(',')})';
    }
    final rows = await db.customSelect(
      'SELECT *, MAX(id) AS id FROM $_table WHERE $where GROUP BY contentId HAVING COUNT(id) > 1',
      variables: variables,
    ).get();
    final duplicates = rows.map((row) => AvesEntry.fromMap(row.data)).toSet();
    if (duplicates.isNotEmpty) {
      _log.d('$runtimeType found duplicates=$duplicates');
    }
    // returns most recent duplicate for each duplicated content ID
    return duplicates;
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.entriesTable, (t) => t.id.equals(id));
  }
}
