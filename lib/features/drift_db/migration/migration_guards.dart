import 'package:drift/native.dart' show SqliteException;

/// Whether [error] is SQLite reporting a schema object this database never had.
///
/// Mirrors the guard used by the reference project's migrations. Index creation
/// is a pure performance artifact, so it tolerates a missing table/column; every
/// other failure (disk full, locked database, corruption) must abort the
/// migration so Drift rolls the schema version back and the next open retries.
bool isMissingSchemaObject(Object error) {
  if (error is! SqliteException) return false;
  final message = error.message;
  return message.contains('no such table') || message.contains('no such column');
}
