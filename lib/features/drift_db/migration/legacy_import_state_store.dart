import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/migration/legacy_import_progress.dart';

/// Lifecycle of the one-time legacy import.
enum LegacyImportStatus { pending, running, done }

/// Typed snapshot of the legacy import state.
class LegacyImportState {
  final LegacyImportStatus status;
  final String? owner;
  final int heartbeatMs;
  final LegacyImportPhase phase;
  final int totalRows;
  final int copiedRows;
  final int tableIndex;
  final String? cursor;

  const new({
    required this.status,
    required this.owner,
    required this.heartbeatMs,
    required this.phase,
    required this.totalRows,
    required this.copiedRows,
    required this.tableIndex,
    required this.cursor,
  });

  /// Whether a `running` owner has stopped refreshing its heartbeat for longer
  /// than [staleMs], meaning it most likely died mid-import.
  bool isStale(int nowMs, int staleMs) => status == LegacyImportStatus.running && nowMs - heartbeatMs >= staleMs;

  LegacyImportProgress toProgress() => LegacyImportProgress(
        phase: phase,
        copiedRows: copiedRows,
        totalRows: totalRows,
  );
}

/// Typed, domain-facing view of the legacy import state, persisted as keys in
/// the generic `appMeta` table.
///
/// The physical key names never leave this store; callers work with
/// [LegacyImportState] and small write methods. Every write here is meant to be
/// called inside a transaction that has already taken the write lock (see
/// [takeWriteLock]), so a read-decide-write transition is atomic across the
/// isolates and processes that share the database.
class LegacyImportStateStore {
  static const statusKey = 'legacyImportState';
  static const ownerKey = 'legacyImportOwner';
  static const heartbeatKey = 'legacyImportHeartbeat';
  static const phaseKey = 'legacyImportPhase';
  static const totalKey = 'legacyImportTotal';
  static const copiedKey = 'legacyImportCopied';
  static const tableIndexKey = 'legacyImportTableIndex';
  static const cursorKey = 'legacyImportCursor';
  static const lockKey = 'legacyImportLock';

  /// Back-compat marker written by the first Drift revision; a database that has
  /// it is treated as already imported even without the newer state keys.
  static const legacyDoneKey = 'legacyImported';

  static const _readKeys = <String>{
    statusKey,
    ownerKey,
    heartbeatKey,
    phaseKey,
    totalKey,
    copiedKey,
    tableIndexKey,
    cursorKey,
    legacyDoneKey,
  };

  final AppMetaStore appMeta;

  new(this.appMeta);

  AppDatabase get db => appMeta.db;

  Future<LegacyImportState> read() async {
    final values = await appMeta.read(_readKeys);
    final status = switch (values[statusKey]) {
      final String name => LegacyImportStatus.values.byName(name),
      null => values[legacyDoneKey] == 'true' ? LegacyImportStatus.done : LegacyImportStatus.pending,
    };
    return LegacyImportState(
      status: status,
      owner: _nonEmpty(values[ownerKey]),
      heartbeatMs: int.tryParse(values[heartbeatKey] ?? '') ?? 0,
      phase: switch (_nonEmpty(values[phaseKey])) {
        final String name => LegacyImportPhase.values.byName(name),
        null => LegacyImportPhase.preparing,
      },
      totalRows: int.tryParse(values[totalKey] ?? '') ?? 0,
      copiedRows: int.tryParse(values[copiedKey] ?? '') ?? 0,
      tableIndex: int.tryParse(values[tableIndexKey] ?? '') ?? 0,
      cursor: _nonEmpty(values[cursorKey]),
    );
  }

  /// Takes SQLite's write lock with a harmless write before a transition reads
  /// the state.
  ///
  /// Drift starts transactions deferred, so a plain read-then-write could see a
  /// stale snapshot and fail to upgrade; writing first gives the surrounding
  /// transaction `BEGIN IMMEDIATE` semantics, which is what serializes the
  /// concurrent importers.
  Future<void> takeWriteLock() => db.customStatement(
        "INSERT OR REPLACE INTO appMeta(key, value) VALUES('$lockKey', '1')",
      );

  /// Claims ownership, or takes over a stale `running` state. Progress keys are
  /// intentionally left untouched so a takeover resumes where the previous
  /// owner stopped.
  Future<void> writeClaim({required String owner, required int nowMs}) => appMeta.write({
        statusKey: LegacyImportStatus.running.name,
        ownerKey: owner,
        heartbeatKey: '$nowMs',
        phaseKey: LegacyImportPhase.preparing.name,
      });

  /// Records the total row count and resets progress for a fresh import.
  Future<void> writeCounting({required String owner, required int totalRows, required int nowMs}) => appMeta.write({
        ownerKey: owner,
        heartbeatKey: '$nowMs',
        phaseKey: LegacyImportPhase.copying.name,
        totalKey: '$totalRows',
        copiedKey: '0',
        tableIndexKey: '0',
        cursorKey: '',
      });

  /// Commits one copied chunk's progress (and refreshes the heartbeat).
  Future<void> writeProgress({
    required int copiedRows,
    required int tableIndex,
    required String? cursor,
    required int nowMs,
  }) =>
      appMeta.write({
        heartbeatKey: '$nowMs',
        copiedKey: '$copiedRows',
        tableIndexKey: '$tableIndex',
        cursorKey: cursor ?? '',
      });

  Future<void> writeVerifying({required int nowMs}) => appMeta.write({
        heartbeatKey: '$nowMs',
        phaseKey: LegacyImportPhase.verifying.name,
      });

  Future<void> writeDone() => appMeta.write({
        statusKey: LegacyImportStatus.done.name,
        ownerKey: '',
        heartbeatKey: '',
        phaseKey: '',
        legacyDoneKey: 'true',
      });

  static String? _nonEmpty(String? value) => (value == null || value.isEmpty) ? null : value;
}
