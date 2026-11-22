import 'dart:io';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Opens a database at [version] by rewinding the current shape.
///
/// The app creates a current-schema file, [downgrade] removes or recreates the
/// objects the tested step is supposed to add, the version is stamped, and a new
/// `AppDatabase` opens the same file so Drift runs the upgrade path.
///
/// Rewinding instead of hand-writing every historical table keeps the fixture
/// honest about the step under test: a column the migration adds is missing, and
/// a table it creates is absent, while the rest of the schema stays valid enough
/// for the later steps to run.
Future<AppDatabase> openDatabaseAt(int version, Future<void> Function(AppDatabase db) downgrade) async {
  final directory = await Directory.systemTemp.createTemp('aves_migration_v$version');
  addTearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });
  final file = File(p.join(directory.path, 'aves.sqlite'));

  final seed = AppDatabase(NativeDatabase(file));
  await seed.customSelect('SELECT 1').get();
  await downgrade(seed);
  await seed.customStatement('PRAGMA user_version = $version');
  await seed.close();

  final db = AppDatabase(NativeDatabase(file));
  addTearDown(db.close);
  // Force the connection open so the upgrade runs before any assertion.
  await db.customSelect('SELECT 1').get();
  return db;
}

/// Names of the schema objects of [type] (`table`, `index`).
Future<Set<String>> databaseObjects(AppDatabase db, String type) async {
  final rows = await db.customSelect(
    'SELECT name FROM sqlite_master WHERE type = ?',
    variables: [Variable.withString(type)],
  ).get();
  return {for (final row in rows) row.data['name'] as String};
}

/// Column names of [table].
Future<Set<String>> columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.data['name'] as String};
}
