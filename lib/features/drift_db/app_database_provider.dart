import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
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

  Future<AppDatabase> open() => _openFuture ??= _open();

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _openFuture = null;
  }

  Future<AppDatabase> _open() async {
    final db = injected ?? AppDatabase(NativeDatabase.createInBackground(File(await _driftPath())));
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
