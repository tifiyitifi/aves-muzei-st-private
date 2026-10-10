import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:flutter/foundation.dart';

/// Owns the `vaults` table (vault configuration, keyed by name).
class VaultStore {
  static const _table = 'vaults';

  final AppDatabase db;

  new(this.db);

  Future<void> clear() async {
    final count = await db.delete(db.vaultsTable).go();
    debugPrint('$runtimeType clear deleted $count rows');
  }

  Future<Set<VaultDetails>> loadAll() async {
    final result = <VaultDetails>{};
    for (final row in await selectAllRows(db, _table)) {
      result.add(VaultDetails.fromMap(row.data));
    }
    return result;
  }

  Future<void> add(Set<VaultDetails> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batchInsertReplace(batch, db.vaultsTable, row.toDbMap());
      }
    });
  }

  Future<void> update(String oldName, VaultDetails row) async {
    await db.batch((batch) {
      batch.deleteWhere(db.vaultsTable, (t) => t.name.equals(oldName));
      batchInsertReplace(batch, db.vaultsTable, row.toDbMap());
    });
  }

  Future<void> remove(Set<VaultDetails> rows) async {
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batch.deleteWhere(db.vaultsTable, (t) => t.name.equals(row.name));
      }
    });
  }
}
