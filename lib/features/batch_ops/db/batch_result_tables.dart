import 'package:drift/drift.dart';

/// One file batch processing wrote into the results folder.
///
/// The row is the only thing that makes a result actionable: the folder alone
/// cannot say which source a copy came from, so "replace the original" and "move
/// it back" are driven by this table. A file in the folder without a row is
/// never touched by the feature.
class BatchResultRows extends Table {
  @override
  String get tableName => 'batch_results';

  /// `${jobId}-${index}`, stable for one item of one job.
  TextColumn get id => text()();

  TextColumn get jobId => text().named('jobId')();

  /// Aves entry id of the source at run time (informational, ids churn).
  IntColumn get sourceEntryId => integer().named('sourceEntryId').nullable()();

  TextColumn get sourceUri => text().named('sourceUri')();

  /// Absolute path of the source file, empty when the entry has no storage path.
  TextColumn get sourcePath => text().named('sourcePath').withDefault(const Constant(''))();

  /// Absolute directory the result is offered to be moved back to.
  TextColumn get sourceDirectory => text().named('sourceDirectory').withDefault(const Constant(''))();

  TextColumn get sourceName => text().named('sourceName')();

  TextColumn get resultUri => text().named('resultUri')();

  TextColumn get resultPath => text().named('resultPath').withDefault(const Constant(''))();

  TextColumn get resultFileName => text().named('resultFileName')();

  TextColumn get resultMimeType => text().named('resultMimeType').withDefault(const Constant(''))();

  IntColumn get resultSizeBytes => integer().named('resultSizeBytes').withDefault(const Constant(0))();

  /// The action chain that produced the result, as profile JSON.
  TextColumn get actionsJson => text().named('actionsJson').withDefault(const Constant(''))();

  IntColumn get createdAt => integer().named('createdAt')();

  /// `pending`, `applied` or `discarded`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A saved action chain the run sheet can reuse.
///
/// [kind] separates normal batch profiles from the copy-share ones, so the next
/// step only adds rows of another kind instead of another table.
class BatchProfileRows extends Table {
  @override
  String get tableName => 'batch_profiles';

  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get actionsJson => text().named('actionsJson').withDefault(const Constant('[]'))();

  /// `batch` or `share`.
  TextColumn get kind => text().withDefault(const Constant('batch'))();

  IntColumn get sortOrder => integer().named('sortOrder').withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().named('isActive').withDefault(const Constant(false))();

  IntColumn get createdAt => integer().named('createdAt')();

  IntColumn get updatedAt => integer().named('updatedAt')();

  @override
  Set<Column> get primaryKey => {id};
}
