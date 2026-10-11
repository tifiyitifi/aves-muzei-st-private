import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:drift/drift.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Owns `dateTaken` + `metadata`. They are written together by [update] and
/// [save], so they live in one slice rather than two.
class CatalogStore {
  static const _metadataTable = 'metadata';
  static const _dateTakenTable = 'dateTaken';

  final AppDatabase db;

  new(this.db);

  Future<void> clearDates() async {
    final count = await db.delete(db.dateTakenTable).go();
    _log.d('$runtimeType clearDates deleted $count rows');
  }

  Future<void> clearMetadata() async {
    final count = await db.delete(db.metadataTable).go();
    _log.d('$runtimeType clearMetadata deleted $count rows');
  }

  Future<Map<int?, int?>> loadDates() async {
    final result = <int?, int?>{};
    for (final row in await selectAllRows(db, _dateTakenTable)) {
      result[row.data['id'] as int] = row.data['dateMillis'] as int? ?? 0;
    }
    return result;
  }

  Future<Set<CatalogMetadata>> loadAll() async {
    final result = <CatalogMetadata>{};
    for (final row in await selectAllRows(db, _metadataTable)) {
      result.add(CatalogMetadata.fromMap(row.data));
    }
    return result;
  }

  Future<Set<CatalogMetadata>> loadByIds(Set<int> ids) => selectByIds(db, _metadataTable, ids, CatalogMetadata.fromMap);

  Future<void> save(Set<CatalogMetadata> entries) async {
    if (entries.isEmpty) return;
    final stopwatch = Stopwatch()..start();
    try {
      await db.batch((batch) {
        for (final metadata in entries) {
          _addToBatch(batch, metadata);
        }
      });
      _log.d('$runtimeType save complete in ${stopwatch.elapsed.inMilliseconds}ms for ${entries.length} entries');
    } catch (error, stack) {
      _log.e('$runtimeType failed to save metadata', error, stack);
    }
  }

  Future<void> update(int id, CatalogMetadata? metadata) async {
    await db.batch((batch) {
      batch.deleteWhere(db.dateTakenTable, (t) => t.id.equals(id));
      batch.deleteWhere(db.metadataTable, (t) => t.id.equals(id));
      _addToBatch(batch, metadata);
    });
  }

  void _addToBatch(Batch batch, CatalogMetadata? metadata) {
    if (metadata == null) return;
    if (metadata.dateMillis != 0) {
      batchInsertReplace(batch, db.dateTakenTable, {
        'id': metadata.id,
        'dateMillis': metadata.dateMillis,
      });
    }
    batchInsertReplace(batch, db.metadataTable, metadata.toDbMap());
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.dateTakenTable, (t) => t.id.equals(id));
    batch.deleteWhere(db.metadataTable, (t) => t.id.equals(id));
  }
}
