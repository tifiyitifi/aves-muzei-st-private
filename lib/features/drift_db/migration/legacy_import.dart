import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';
import 'package:aves/features/drift_db/migration/legacy_import_state_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/db/db_sqflite_schema.dart';
import 'package:aves/model/db/db_sqflite_upgrade.dart';
import 'package:drift/drift.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

const _log = AreaKeyLog(LogKeys.db);

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

  /// How many times a verification mismatch may restart the copy before the
  /// failure is raised. A deterministic defect fails again immediately, so one
  /// re-import is enough to absorb a transient inconsistency.
  final int maxReimports;

  final LegacyImportStateStore _state;

  new(
    this.db,
    this.appMeta, {
    this.chunkSize = 5000,
    this.staleMs = 60000,
    this.pollInterval = const Duration(milliseconds: 500),
    this.maxReimports = 1,
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

  /// Small, user-defined tables whose primary key is a text id, mapped to the
  /// key column used to chunk their copy. They grow with the user's own data
  /// (one cover/dynamic album/vault per filter), so they are paginated like the
  /// id-keyed tables instead of being loaded whole into memory.
  static const _textKeyedTables = <String, String>{
    'covers': 'filter',
    'dynamicAlbums': 'name',
    'vaults': 'name',
  };

  /// Whether the table at [tableIndex] is text-keyed, so its persisted cursor is
  /// a key rather than an integer.
  static bool _isTextKeyed(int tableIndex) => tableIndex >= 0 && tableIndex < _legacyTables.length && _textKeyedTables.containsKey(_legacyTables[tableIndex]);

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
      var reimports = 0;
      while (true) {
        await _copyTables(owner: owner, legacy: legacy, onProgress: onProgress);

        final mismatches = await db.transaction(() async {
          await _state.takeWriteLock();
          if (!await _owns(owner)) throw const _LostOwnership();
          await _state.writeVerifying(nowMs: _now);
          final result = await _verifyCounts(legacy);
          // Commit `done` in the same transaction as a clean verification, so the
          // import is never left verified-but-not-done.
          if (result.isEmpty) await _state.writeDone();
          return result;
        });

        if (mismatches.isEmpty) break;

        // A copy defect leaves a state that verification keeps rejecting; report
        // the row-level diff and reconcile from a clean slate instead of failing
        // (and re-failing on every launch) against the same bad state.
        _log.w('$runtimeType legacy import mismatch: ${mismatches.map((m) => m.describe()).join('; ')}');
        if (reimports++ >= maxReimports) {
          throw LegacyImportVerifyException(mismatches.map((m) => m.describe()).toList());
        }
        await _restartImport(owner);
        onProgress?.call(const LegacyImportProgress(phase: LegacyImportPhase.preparing, copiedRows: 0, totalRows: 0));
      }
    } on _LostOwnership {
      return false;
    } finally {
      await legacy.close();
    }

    // The legacy handle must be closed first: renaming an open file fails on
    // Windows (and the rename is only a rollback backup, so it runs last).
    await _keepBackup(legacyFile, legacyPath);
    _log.i('$runtimeType imported legacy db into drift');
    return true;
  }

  /// Copies every legacy table, resuming from the committed progress cursor.
  Future<void> _copyTables({
    required String owner,
    required sqflite.Database legacy,
    void Function(LegacyImportProgress)? onProgress,
  }) async {
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

    // The cursor is plain text in appMeta; a hand-edited or corrupt value must
    // not brick the import (an int parse would throw on every retry). Rewind and
    // recopy from a clean slate instead, like a verification mismatch does. A
    // text-keyed table's cursor is legitimately non-numeric, so only id-keyed
    // tables are validated here.
    if (!_isTextKeyed(state.tableIndex) && state.cursor != null && int.tryParse(state.cursor!) == null) {
      _log.w('$runtimeType discarding corrupt legacy import cursor=${state.cursor}, restarting');
      await _restartImport(owner);
      state = await _state.read();
    }

    onProgress?.call(state.toProgress());

    var copied = state.copiedRows;
    final totalRows = state.totalRows;

    for (var tableIndex = state.tableIndex; tableIndex < _legacyTables.length; tableIndex++) {
      final table = _legacyTables[tableIndex];
      final textKeyColumn = _textKeyedTables[table];
      var cursor = tableIndex == state.tableIndex ? state.cursor : null;
      while (true) {
        final rows = textKeyColumn != null
            ? await _queryTextChunk(legacy, table, textKeyColumn, cursor)
            : await _queryChunk(legacy, table, cursor);
        if (rows.isEmpty) break;
        final lastKey = textKeyColumn != null ? rows.last[textKeyColumn] as String : '${rows.last['id'] as int}';
        await _commitChunk(
          owner: owner,
          table: table,
          rows: rows,
          copiedRows: copied + rows.length,
          tableIndex: tableIndex,
          cursor: lastKey,
        );
        copied += rows.length;
        cursor = lastKey;
        onProgress?.call(LegacyImportProgress(phase: LegacyImportPhase.copying, copiedRows: copied, totalRows: totalRows));
      }
    }
  }

  /// Drops the copied rows and rewinds the cursor so the next pass re-copies
  /// every table from the top. Safe because writers gate on `init()`: while the
  /// import runs, no other actor has touched these tables yet.
  Future<void> _restartImport(String owner) => db.transaction(() async {
        await _state.takeWriteLock();
        if (!await _owns(owner)) throw const _LostOwnership();
        await db.batch((batch) {
          batch.deleteAll(db.entriesTable);
          batch.deleteAll(db.dateTakenTable);
          batch.deleteAll(db.metadataTable);
          batch.deleteAll(db.addressesTable);
          batch.deleteAll(db.favouritesTable);
          batch.deleteAll(db.coversTable);
          batch.deleteAll(db.dynamicAlbumsTable);
          batch.deleteAll(db.vaultsTable);
          batch.deleteAll(db.trashTable);
          batch.deleteAll(db.videoPlaybackTable);
          batch.deleteAll(db.debugTable);
        });
        await _state.writeRestart(owner: owner, nowMs: _now);
      });

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

  /// One keyset page of a text-keyed table, ordered by its text key.
  Future<List<Map<String, Object?>>> _queryTextChunk(sqflite.Database legacy, String table, String column, String? cursor) {
    if (cursor == null) {
      return legacy.rawQuery('SELECT * FROM $table ORDER BY $column LIMIT $chunkSize');
    }
    return legacy.rawQuery('SELECT * FROM $table WHERE $column > ? ORDER BY $column LIMIT $chunkSize', [cursor]);
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

  /// Compares every table's row count against the legacy source, returning the
  /// differences (empty when the import is consistent) instead of throwing, so
  /// the caller can diagnose and reconcile them.
  Future<List<_TableMismatch>> _verifyCounts(sqflite.Database legacy) async {
    final mismatches = <_TableMismatch>[];
    for (final table in _legacyTables) {
      final legacyRows = await legacy.rawQuery('SELECT COUNT(*) AS c FROM $table');
      final legacyCount = legacyRows.first['c'] as int? ?? 0;
      final driftRows = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
      final driftCount = driftRows.first.data['c'] as int? ?? 0;
      if (legacyCount != driftCount) {
        mismatches.add(await _describeMismatch(legacy, table, legacyCount, driftCount));
      }
    }
    return mismatches;
  }

  /// Builds a mismatch record and, for id-keyed tables, samples the differing
  /// ids so the failure is diagnosable instead of just two counts.
  Future<_TableMismatch> _describeMismatch(sqflite.Database legacy, String table, int legacyCount, int driftCount) async {
    if (_textKeyedTables.containsKey(table)) {
      return _TableMismatch(table: table, legacyCount: legacyCount, driftCount: driftCount);
    }
    final (missingIds, extraIds) = await _sampleIdDiff(legacy, table);
    return _TableMismatch(
      table: table,
      legacyCount: legacyCount,
      driftCount: driftCount,
      missingIds: missingIds,
      extraIds: extraIds,
    );
  }

  /// Samples the ids present in only one of the two tables.
  ///
  /// Both sides are streamed in ascending id order one page at a time and diffed
  /// as a merge, so memory stays bounded even for a library with hundreds of
  /// thousands of rows (loading either side's full id set risked an OOM).
  /// Returns `(missing, extra)`: legacy-only and drift-only ids, each capped at
  /// [_diagnosticSampleSize].
  Future<(List<int>, List<int>)> _sampleIdDiff(sqflite.Database legacy, String table) async {
    final legacyIds = StreamIterator(
      _pageIds((cursor) => legacy.rawQuery(_idPageSql(table, cursor), cursor == null ? null : [cursor]).then((rows) => rows.map((row) => row['id'] as int).toList())),
    );
    final driftIds = StreamIterator(
      _pageIds((cursor) => db.customSelect(_idPageSql(table, cursor), variables: cursor == null ? const [] : [Variable.withInt(cursor)]).get().then((rows) => rows.map((row) => row.data['id'] as int).toList())),
    );

    final missing = <int>[];
    final extra = <int>[];
    var hasLegacy = await legacyIds.moveNext();
    var hasDrift = await driftIds.moveNext();
    try {
      while ((missing.length < _diagnosticSampleSize || extra.length < _diagnosticSampleSize) && (hasLegacy || hasDrift)) {
        final legacyId = hasLegacy ? legacyIds.current : null;
        final driftId = hasDrift ? driftIds.current : null;
        if (driftId == null || (legacyId != null && legacyId < driftId)) {
          missing.add(legacyId!);
          hasLegacy = await legacyIds.moveNext();
        } else if (legacyId == null || driftId < legacyId) {
          extra.add(driftId);
          hasDrift = await driftIds.moveNext();
        } else {
          hasLegacy = await legacyIds.moveNext();
          hasDrift = await driftIds.moveNext();
        }
      }
    } finally {
      await legacyIds.cancel();
      await driftIds.cancel();
    }
    return (missing, extra);
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
      _log.d('$runtimeType kept legacy db backup at ${backup.path}');
    } catch (error) {
      _log.w('$runtimeType could not back up legacy db', error);
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

/// Rows sampled per mismatched table when reporting a verification difference.
const _diagnosticSampleSize = 16;

/// Rows fetched per keyset page while sampling the ids of a mismatched table.
const _idPageSize = 1000;

/// `SELECT id` for one ascending keyset page.
String _idPageSql(String table, int? cursor) => 'SELECT id FROM $table ${cursor == null ? '' : 'WHERE id > ?'} ORDER BY id LIMIT $_idPageSize';

/// Lazily pages ascending ids from [fetch] via keyset pagination, so a caller
/// can diff two sources without materializing either side in memory.
Stream<int> _pageIds(Future<List<int>> Function(int? cursor) fetch) async* {
  int? cursor;
  while (true) {
    final page = await fetch(cursor);
    if (page.isEmpty) break;
    for (final id in page) {
      yield id;
      cursor = id;
    }
  }
}

/// One table's verification difference, with a bounded id sample for diagnosis.
class _TableMismatch {
  final String table;
  final int legacyCount;
  final int driftCount;
  final List<int> missingIds;
  final List<int> extraIds;

  const new({
    required this.table,
    required this.legacyCount,
    required this.driftCount,
    this.missingIds = const [],
    this.extraIds = const [],
  });

  String describe() => 'table=$table legacy=$legacyCount drift=$driftCount missingIds=$missingIds extraIds=$extraIds';
}

/// Thrown when the legacy import still fails verification after the allowed
/// re-imports, carrying a per-table diff so the failure is diagnosable.
class LegacyImportVerifyException implements Exception {
  final List<String> details;

  const new(this.details);

  @override
  String toString() => '$runtimeType: ${details.join('; ')}';
}
