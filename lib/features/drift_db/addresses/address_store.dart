import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:drift/drift.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Owns the `address` table (reverse-geocoded location metadata).
class AddressStore {
  static const _table = 'address';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.addressesTable).go();
    _log.d('$runtimeType clear deleted $count rows');
  }

  Future<Set<AddressDetails>> loadAll() async {
    final result = <AddressDetails>{};
    for (final row in await selectAllRows(db, _table)) {
      result.add(AddressDetails.fromMap(row.data));
    }
    return result;
  }

  Future<Set<AddressDetails>> loadByIds(Set<int> ids) => selectByIds(db, _table, ids, AddressDetails.fromMap);

  Future<void> save(Set<AddressDetails> addresses) async {
    if (addresses.isEmpty) return;
    final stopwatch = Stopwatch()..start();
    await db.batch((batch) {
      for (final address in addresses) {
        batchInsertReplace(batch, db.addressesTable, address.toDbMap());
      }
    });
    _log.d('$runtimeType save complete in ${stopwatch.elapsed.inMilliseconds}ms for ${addresses.length} entries');
  }

  Future<void> update(int id, AddressDetails? address) async {
    await db.batch((batch) {
      batch.deleteWhere(db.addressesTable, (t) => t.id.equals(id));
      if (address != null) {
        batchInsertReplace(batch, db.addressesTable, address.toDbMap());
      }
    });
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.addressesTable, (t) => t.id.equals(id));
  }
}
