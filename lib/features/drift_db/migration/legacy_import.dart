import 'dart:io';
import 'dart:math';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';
import 'package:aves/features/drift_db/migration/legacy_import_state_store.dart';
import 'package:aves/model/db/db_sqflite_schema.dart';
import 'package:aves/model/db/db_sqflite_upgrade.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// One-time, forward-only import of the legacy `metadata.db` (sqflite, v16)
/// into the fork-owned `aves.drift.db`.
///
/// Design (see AGENTS "Persistence & database"):
/// - Any entrypoint (main, analysis, global search, widget) may call this, so
///   ownership is decided in the database: a state transition takes SQLite's
///   write lock first, then claims / takes over / finalizes atomically. Exactly
///   one actor imports; the others observe the committed state and no-op.
/// - The copy is chunked and each chunk commits its rows together with its
///   progress cursor, so the UI can show real counts and an interrupted run
///   resumes from the last committed row instead of starting over.
/// - A crashed owner stops refreshing its heartbeat, so the next launch takes
///   over a stale `running` state and resumes.
/// - The `done` marker is only written once every table has been verified, so a
///   partial import can never look complete.
/// - The legacy file is kept on disk as `metadata.db.imported` for rollback.
///
/// This is the one place that legitimately knows the whole legacy physical
/// schema: it is a cross-cutting data migration, not a domain operation, so it
/// enumerates the tables directly instead of going through the domain stores.
class LegacyImport {
  final AppDatabase db;
  final AppMetaStore appMeta;

  /// Rows copied per transaction. Large enough to amortize commits, small
  /// enough that progress moves and an interrupted run loses little work.
  final int chunkSize;

  /// How long a `running` owner may go without a heartbeat before another actor
  /// takes over.
  final int staleMs;

  /// How often a waiting actor re-checks the shared state.
  final Duration pollInterval;

  final LegacyImportStateStore _state;

  new(
    this.db,
    this.appMeta, {
    this.chunkSize = 5000,
    this.staleMs = 60000,
    this.pollInterval = const Duration(milliseconds: 500),
  }) : _state = LegacyImportStateStore(appMeta);

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

  /// Small, user-defined tables whose primary key is a text id, copied whole.
  static const _textKeyedTables = <String>{'covers', 'dynamicAlbums', 'vaults'};

  Future<void> runIfNeeded({
    required String legacyPath,
    void Function(LegacyImportProgress)? onProgress,
  }) async {
    if ((await _state.read()).status == LegacyImportStatus.done) return;

    final legacyFile = File(legacyPath);
    if (!legacyFile.existsSync()) {
      // Fresh install, or the legacy file was already imported and renamed.
      await _markDone();
      return;
    }

    final owner = _newOwnerToken();
    while (true) {
      final state = await _state.read();
      if (state.status == LegacyImportStatus.done) return;

      // Only contend for the write lock when a claim is actually possible;
      // while another actor is importing, this stays a cheap read-only poll.
      if (state.status == LegacyImportStatus.pending || state.isStale(_now, staleMs)) {
        final claim = await _claimOrTakeover(owner);
        if (claim == _Claim.done) return;
        if (claim == _Claim.owned) {
          final finished = await _importAsOwner(
            owner: owner,
            legacyFile: legacyFile,
            legacyPath: legacyPath,
            onProgress: onProgress,
          );
          if (finished) return;
          // Lost ownership to a takeover: report the new owner's progress and
          // wait for it instead of failing the whole setup.
          continue;
        }
      }

      onProgress?.call(state.toProgress());
      await Future.delayed(pollInterval);
    }
  }

  /// Claims ownership if the import is pending or the previous owner went stale,
  /// otherwise reports whether it is already done or someone else is on it.
  Future<_Claim> _claimOrTakeover(String owner) async {
    final now = _now;
    return db.transaction(() async {
      await _state.takeWriteLock();
      final state = await _state.read();
      if (state.status == LegacyImportStatus.done) return _Claim.done;
      if (state.status == LegacyImportStatus.running && !state.isStale(now, staleMs)) return _Claim.busy;
      await _state.writeClaim(owner: owner, nowMs: now);
      return _Claim.owned;
    });
  }

  Future<bool> _importAsOwner({
    required String owner,
    required File legacyFile,
    required String legacyPath,
    void Function(LegacyImportProgress)? onProgress,
  }) async {
    if (!legacyFile.existsSync()) {
      await _markDone();
      return true;
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
      var state = await _state.read();
      if (state.totalRows == 0) {
        // First owner: count once, then reset progress.
        final totalRows = await _countLegacyRows(legacy);
        await db.transaction(() async {
          await _state.takeWriteLock();
          if (!await _owns(owner)) throw const _LostOwnership();
          await _state.writeCounting(owner: owner, totalRows: totalRows, nowMs: _now);
        });
        state = await _state.read();
      }
      onProgress?.call(state.toProgress());

      var tableIndex = state.tableIndex;
      var copied = state.copiedRows;
      final totalRows = state.totalRows;

      for (; tableIndex < _legacyTables.length; tableIndex++) {
        final table = _legacyTables[tableIndex];
        if (_textKeyedTables.contains(table)) {
          final rows = await legacy.query(table);
          if (rows.isNotEmpty) {
            await _commitChunk(
              owner: owner,
              table: table,
              rows: rows,
              copiedRows: copied + rows.length,
              tableIndex: tableIndex + 1,
              cursor: null,
            );
            copied += rows.length;
            onProgress?.call(LegacyImportProgress(phase: LegacyImportPhase.copying, copiedRows: copied, totalRows: totalRows));
          }
        } else {
          var cursor = tableIndex == state.tableIndex ? state.cursor : null;
          while (true) {
            final rows = await _queryChunk(legacy, table, cursor);
            if (rows.isEmpty) break;
            final lastId = '${rows.last['id'] as int}';
            await _commitChunk(
              owner: owner,
              table: table,
              rows: rows,
              copiedRows: copied + rows.length,
              tableIndex: tableIndex,
              cursor: lastId,
            );
            copied += rows.length;
            cursor = lastId;
            onProgress?.call(LegacyImportProgress(phase: LegacyImportPhase.copying, copiedRows: copied, totalRows: totalRows));
          }
        }
      }

      await db.transaction(() async {
        await _state.takeWriteLock();
        if (!await _owns(owner)) throw const _LostOwnership();
        await _state.writeVerifying(nowMs: _now);
        await _verifyCounts(legacy);
        await _state.writeDone();
      });
    } on _LostOwnership {
      return false;
    } finally {
      await legacy.close();
    }

    // The legacy handle must be closed first: renaming an open file fails on
    // Windows (and the rename is only a rollback backup, so it runs last).
    await _keepBackup(legacyFile, legacyPath);
    debugPrint('$runtimeType imported legacy db into drift');
    return true;
  }

  /// Copies one chunk in a transaction that also commits its progress cursor.
  ///
  /// Taking the write lock and re-checking ownership inside the same
  /// transaction fences a displaced owner out: if another actor took over, this
  /// throws and the chunk (and its progress) rolls back together.
  Future<void> _commitChunk({
    required String owner,
    required String table,
    required List<Map<String, Object?>> rows,
    required int copiedRows,
    required int tableIndex,
    required String? cursor,
  }) async {
    final insert = _inserter(table);
    await db.transaction(() async {
      await _state.takeWriteLock();
      if (!await _owns(owner)) throw const _LostOwnership();
      await db.batch((batch) => insert(batch, rows));
      await _state.writeProgress(copiedRows: copiedRows, tableIndex: tableIndex, cursor: cursor, nowMs: _now);
    });
  }

  Future<bool> _owns(String owner) async {
    final state = await _state.read();
    return state.status == LegacyImportStatus.running && state.owner == owner;
  }

  Future<List<Map<String, Object?>>> _queryChunk(sqflite.Database legacy, String table, String? cursor) {
    if (cursor == null) {
      return legacy.rawQuery('SELECT * FROM $table ORDER BY id LIMIT $chunkSize');
    }
    return legacy.rawQuery('SELECT * FROM $table WHERE id > ? ORDER BY id LIMIT $chunkSize', [int.parse(cursor)]);
  }

  void Function(Batch batch, List<Map<String, Object?>> rows) _inserter(String table) {
    switch (table) {
      case 'entry':
        return (batch, rows) => _insertAll(batch, db.entriesTable, rows);
      case 'dateTaken':
        return (batch, rows) => _insertAll(batch, db.dateTakenTable, rows);
      case 'metadata':
        return (batch, rows) => _insertAll(batch, db.metadataTable, rows);
      case 'address':
        return (batch, rows) => _insertAll(batch, db.addressesTable, rows);
      case 'favourites':
        return (batch, rows) => _insertAll(batch, db.favouritesTable, rows);
      case 'covers':
        return (batch, rows) => _insertAll(batch, db.coversTable, rows);
      case 'dynamicAlbums':
        return (batch, rows) => _insertAll(batch, db.dynamicAlbumsTable, rows);
      case 'vaults':
        return (batch, rows) => _insertAll(batch, db.vaultsTable, rows);
      case 'trash':
        return (batch, rows) => _insertAll(batch, db.trashTable, rows);
      case 'videoPlayback':
        return (batch, rows) => _insertAll(batch, db.videoPlaybackTable, rows);
      case 'debug':
        return (batch, rows) => _insertAll(batch, db.debugTable, rows);
      default:
        throw StateError('unknown legacy table=$table');
    }
  }

  static void _insertAll<T extends Table, D>(Batch batch, TableInfo<T, D> table, List<Map<String, Object?>> rows) {
    for (final row in rows) {
      batchInsertReplace(batch, table, row);
    }
  }

  Future<int> _countLegacyRows(sqflite.Database legacy) async {
    var total = 0;
    for (final table in _legacyTables) {
      final rows = await legacy.rawQuery('SELECT COUNT(*) AS c FROM $table');
      total += rows.first['c'] as int? ?? 0;
    }
    return total;
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

  Future<void> _markDone() async {
    await db.transaction(() async {
      await _state.takeWriteLock();
      await _state.writeDone();
    });
  }

  /// Keeps the legacy file on disk as `metadata.db.imported` instead of
  /// deleting it, so the pre-migration data stays inspectable for
  /// traceability/rollback. Leftover sqflite side files (e.g.
  /// `metadata.db-journal`) are likewise left in place; they are inert once the
  /// database has been renamed.
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

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static String _newOwnerToken() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }
}

enum _Claim { done, owned, busy }

/// Thrown inside a transaction when another actor took over ownership, so the
/// chunk rolls back and this actor returns to waiting.
class _LostOwnership implements Exception {
  const new();
}
