import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Lazily creates the single per-isolate [AppDatabase] connection and memoizes
/// it, so the metadata-settings store (v2) and `DriftLocalMediaDb` share one
/// connection instead of opening two.
///
/// Opening is deliberately split from the legacy media import: v2 settings must
/// be readable at `settings.init()`, which runs before `DriftLocalMediaDb.init()`
/// (and its potentially long one-time import).
class AppDatabaseProvider {
  new({this.injected});

  static const String dbFileName = 'aves.drift.db';

  /// Optional injected connection, used by tests.
  final AppDatabase? injected;
  AppDatabase? _db;
  Future<AppDatabase>? _openFuture;

  bool get isInjected => injected != null;

  /// Opens (or returns the already-open) connection.
  ///
  /// Concurrent callers share the in-flight attempt, but a *failed* attempt is
  /// dropped so a later call retries: a transient open failure (e.g. a busy
  /// disk) must not poison the provider for the rest of the process. This
  /// mirrors the retry in `DriftLocalMediaDb.init()`; without it, that retry
  /// would keep receiving the same cached failure.
  Future<AppDatabase> open() async {
    final attempt = _openFuture ??= _open();
    try {
      return await attempt;
    } catch (_) {
      if (identical(_openFuture, attempt)) _openFuture = null;
      rethrow;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _openFuture = null;
  }

  /// Creates the connection. Overridable so tests can simulate an open failure
  /// without a real platform database path.
  @protected
  Future<AppDatabase> createDatabase() async => injected ?? AppDatabase(NativeDatabase.createInBackground(File(await _driftPath())));

  Future<AppDatabase> _open() async {
    final db = await createDatabase();
    // Force the connection open so onCreate/beforeOpen complete before callers
    // read or write.
    await db.customSelect('SELECT 1').get();
    _db = db;
    return db;
  }

  Future<String> _driftPath() async {
    final databasesPath = await sqflite.getDatabasesPath();
    return pContext.join(databasesPath, dbFileName);
  }
}
