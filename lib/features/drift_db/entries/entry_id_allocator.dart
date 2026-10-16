import 'dart:math';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Hands out entry ids without collisions across the connections that share the
/// database file.
///
/// Entry ids are caller-provided (see `LocalMediaDb.nextId`), and the app opens
/// one connection per isolate (main app, analysis service, global search). A
/// plain per-isolate `MAX(id) + 1` counter would let two writers hand out the
/// same id and silently clobber each other through `INSERT OR REPLACE`.
///
/// So each allocator reserves disjoint *blocks* from a persisted high-water
/// mark; the claim runs in a write transaction, which serializes concurrent
/// connections. The next block is reserved in the background once the current
/// one gets low, so the synchronous [next] never waits on the database.
class EntryIdAllocator {
  /// Bookkeeping key in the generic `appMeta` table.
  static const highWaterKey = 'entryIdHighWater';

  /// Ids reserved per claim. Large enough that the background top-up (one small
  /// transaction) lands well before the block runs dry.
  static const defaultBlockSize = 100000;

  final AppDatabase db;
  final EntryStore entries;
  final AppMetaStore appMeta;
  final int blockSize;

  int _cursor = 0;
  int _ceiling = 0;
  Future<void>? _toppingUp;

  new(this.db, this.entries, this.appMeta, {this.blockSize = defaultBlockSize});

  /// Reserves the first block; call once during initialization.
  Future<void> init() => _reserve();

  /// The next id. Never reused, and disjoint from the ids another allocator
  /// hands out for the same database.
  ///
  /// Throws [StateError] if the current block runs dry before the background
  /// top-up lands. [next] is synchronous, so only a caller that hands out more
  /// than `blockSize ~/ 2` ids (where the top-up starts) in one uninterrupted
  /// synchronous loop can reach this; a caller that yields to the event loop
  /// between ids lets the top-up land. The only such call site today is a bulk
  /// copy assigning ids in a plain `forEach` (`CollectionSource.updateAfterMove`),
  /// which can synchronize with [settled] instead of racing it (it does not
  /// today). The `blockSize` in the message sizes the gap for diagnosis.
  int next() {
    if (_cursor >= _ceiling) {
      throw StateError('$runtimeType exhausted its id block before the background top-up landed (blockSize=$blockSize)');
    }
    final id = ++_cursor;
    if (_ceiling - _cursor < blockSize ~/ 2) _topUp();
    return id;
  }

  /// Completes once any in-flight background reservation has settled. Lets a
  /// caller synchronize with the top-up instead of racing it.
  Future<void> get settled async {
    var pending = _toppingUp;
    while (pending != null) {
      await pending;
      pending = _toppingUp;
    }
  }

  void _topUp() {
    if (_toppingUp != null) return;
    _toppingUp = _reserve().then((_) {}, onError: (Object error, StackTrace stack) {
      // A failed top-up leaves the current block intact; the next [next] call
      // retries it, and a true exhaustion surfaces as a clear [StateError].
      _log.w('$runtimeType failed to reserve the next entry id block', error, stack);
    }).whenComplete(() => _toppingUp = null);
  }

  Future<void> _reserve() async {
    final (low, high) = await db.transaction(() async {
      // Take the write lock first so the read-decide-write claim is atomic
      // across connections (drift starts transactions deferred).
      await _takeWriteLock();
      final stored = int.tryParse((await appMeta.read({highWaterKey}))[highWaterKey] ?? '') ?? 0;
      // A database that predates this allocator has entries but no high-water
      // mark, so never hand out an id at or below the current maximum.
      final floor = await entries.maxId();
      final low = max(stored, floor);
      final high = low + blockSize;
      await appMeta.write({highWaterKey: '$high'});
      return (low, high);
    });
    // Jump to the freshly reserved block; every id behind `low` is either
    // already handed out or belongs to another allocator, so nothing is reused.
    _cursor = low;
    _ceiling = high;
  }

  Future<void> _takeWriteLock() => db.customStatement("INSERT OR REPLACE INTO appMeta(key, value) VALUES('$highWaterKey.lock', '1')");
}
