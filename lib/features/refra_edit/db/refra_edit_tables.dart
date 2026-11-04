import 'package:drift/drift.dart';

/// One edit session, always rooted at a staged copy.
///
/// The fork never edits the user's original: a session first copies the source into
/// `Pictures/aves_refra_edit/<id>` and every editor (built-in or third-party) works on that copy.
/// The row remembers where the source came from so the copy can be moved back later, and the
/// original stays readable throughout.
class RefraEditSessionRows extends Table {
  @override
  String get tableName => 'refra_edit_sessions';

  /// Session id, also the staging sub-directory name.
  TextColumn get id => text()();

  /// Aves entry id of the source at the time the session started (informational, ids churn).
  IntColumn get sourceEntryId => integer().named('sourceEntryId').nullable()();

  TextColumn get sourceUri => text().named('sourceUri')();

  /// Absolute path of the source file, empty when the entry has no storage path.
  TextColumn get sourcePath => text().named('sourcePath').withDefault(const Constant(''))();

  /// Absolute directory the edited copy is offered to be moved back to.
  TextColumn get sourceDirectory => text().named('sourceDirectory').withDefault(const Constant(''))();

  TextColumn get sourceName => text().named('sourceName')();

  TextColumn get sourceMimeType => text().named('sourceMimeType')();

  /// Absolute staging directory (`Pictures/aves_refra_edit/<id>`).
  TextColumn get stagingDirectory => text().named('stagingDirectory')();

  /// Uri of the initial staged copy.
  TextColumn get stagedUri => text().named('stagedUri')();

  IntColumn get createdAt => integer().named('createdAt')();

  /// `active` while the copies still live in the staging directory, `moved` once every kept
  /// output has been moved back, `discarded` when the user deleted the copies.
  TextColumn get status => text().withDefault(const Constant('active'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One file produced by a session.
///
/// The staged copy itself is output `staged`; every "save a copy", RAW export or editor round-trip
/// that leaves a new file adds another row, which is what the session page counts as results.
class RefraEditOutputRows extends Table {
  @override
  String get tableName => 'refra_edit_outputs';

  TextColumn get id => text()();

  TextColumn get sessionId => text().named('sessionId')();

  TextColumn get uri => text()();

  TextColumn get path => text().withDefault(const Constant(''))();

  TextColumn get fileName => text().named('fileName')();

  /// `staged`, `built_in`, `external` or `unknown` for files found by rescanning the folder.
  TextColumn get kind => text()();

  IntColumn get sizeBytes => integer().named('sizeBytes').withDefault(const Constant(0))();

  IntColumn get createdAt => integer().named('createdAt')();

  @override
  Set<Column> get primaryKey => {id};
}
