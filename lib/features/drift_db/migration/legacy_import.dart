import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/model/db/db_sqflite_schema.dart';
import 'package:aves/model/db/db_sqflite_upgrade.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// One-time, forward-only import of the legacy `metadata.db` (sqflite, v16)
/// into the fork-owned `aves.drift.db`.
///
/// Design constraints (see AGENTS "Persistence & database"):
/// - Runs in a single Drift transaction that also writes the `appMeta` guard
///   flag, so a crash can never leave a half-applied import looking done; the
///   next open simply retries.
/// - Row counts are verified per table before committing, so a partial read
///   aborts instead of silently dropping user data.
/// - The legacy file is kept on disk as `metadata.db.imported` for rollback.
///
/// This is the one place that legitimately knows the whole legacy physical
/// schema: it is a cross-cutting data migration, not a domain operation, so it
/// enumerates the tables directly instead of going through the domain stores.
class LegacyImport {
  final AppDatabase db;
  final AppMetaStore appMeta;

  new(this.db, this.appMeta);

  static const legacyDbFileName = 'metadata.db';
  static const importedBackupFileName = 'metadata.db.imported';

  /// Legacy table names, in copy order. Drift table names match exactly.
  static const _legacyTables = <String>[
    'entry',
    'dateTaken',
    'metadata',
    'address',
    'favourites',
    'covers',
    'dynamicAlbums',
    'vaults',
    'trash',
    'videoPlayback',
    'debug',
  ];

  Future<void> runIfNeeded({required String legacyPath}) async {
    if (await appMeta.isLegacyImported()) return;

    final legacyFile = File(legacyPath);
    if (!legacyFile.existsSync()) {
      // Fresh install, or the legacy file was already imported and renamed.
      await appMeta.markLegacyImported();
      return;
    }

    // Reuse the existing sqflite upgrader to bring any older legacy file to v16
    // before copying, instead of re-implementing the v1->v16 history in Drift.
    final legacy = await sqflite.openDatabase(
      legacyPath,
      version: 16,
      onCreate: (database, version) => SqfliteLocalMediaDbSchema.createLatestVersion(database),
      onUpgrade: LocalMediaDbUpgrader.upgradeDb,
    );
    try {
      await db.transaction(() async {
        await _copyAll(legacy);
        await _verifyCounts(legacy);
        await appMeta.markLegacyImported();
      });
    } finally {
      await legacy.close();
    }

    await _keepBackup(legacyFile, legacyPath);
  }

  Future<void> _copyAll(sqflite.Database legacy) async {
    await _copy(legacy, db.entriesTable, 'entry');
    await _copy(legacy, db.dateTakenTable, 'dateTaken');
    await _copy(legacy, db.metadataTable, 'metadata');
    await _copy(legacy, db.addressesTable, 'address');
    await _copy(legacy, db.favouritesTable, 'favourites');
    await _copy(legacy, db.coversTable, 'covers');
    await _copy(legacy, db.dynamicAlbumsTable, 'dynamicAlbums');
    await _copy(legacy, db.vaultsTable, 'vaults');
    await _copy(legacy, db.trashTable, 'trash');
    await _copy(legacy, db.videoPlaybackTable, 'videoPlayback');
    await _copy(legacy, db.debugTable, 'debug');
  }

  Future<void> _copy<T extends Table, D>(sqflite.Database legacy, TableInfo<T, D> table, String tableName) async {
    final rows = await legacy.query(tableName);
    if (rows.isEmpty) return;
    await db.batch((batch) {
      for (final row in rows) {
        batch.insert(table, rawInsertable<D>(row), mode: InsertMode.insertOrReplace);
      }
    });
  }

  Future<void> _verifyCounts(sqflite.Database legacy) async {
    for (final table in _legacyTables) {
      final legacyRows = await legacy.rawQuery('SELECT COUNT(*) AS c FROM $table');
      final legacyCount = legacyRows.first['c'] as int? ?? 0;
      final driftRows = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
      final driftCount = driftRows.first.data['c'] as int? ?? 0;
      if (legacyCount != driftCount) {
        throw StateError('legacy import mismatch for $table: legacy=$legacyCount drift=$driftCount');
      }
    }
  }

  Future<void> _keepBackup(File legacyFile, String legacyPath) async {
    try {
      if (!legacyFile.existsSync()) return;
      final dir = legacyPath.substring(0, legacyPath.length - legacyDbFileName.length);
      final backup = File('$dir$importedBackupFileName');
      if (backup.existsSync()) await backup.delete();
      await legacyFile.rename(backup.path);
      debugPrint('$runtimeType kept legacy db backup at ${backup.path}');
    } catch (error) {
      debugPrint('$runtimeType could not back up legacy db: $error');
    }
  }
}
