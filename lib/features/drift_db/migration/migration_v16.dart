import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:drift/drift.dart';

/// Schema v15 -> v16: one media-store row per file.
///
/// A file can be reported to the database more than once — a rescan, an edit
/// transfer and a retried import each hand over the same media-store item — and
/// every report took a fresh row id. The rows were identical in path and
/// media-store id, so the library showed the photo twice, and the grid mounted
/// two tiles with the same hero tag: that trips Flutter's "multiple heroes
/// share the same tag" assertion on any route change out of the collection.
///
/// The duplicates are merged into the oldest row (favourites, covers, pins and
/// bookmarks are keyed on entry ids, so the survivor has to be the one those
/// references most likely point at), then a partial unique index makes a
/// repeated report a no-op instead of a second row. The index is partial on
/// purpose: rows without a media-store id, and vault rows, have no identity to
/// collapse on.
///
/// The identity is the content id *within one collection*: MediaStore numbers
/// the image and video tables independently, so the same number can name two
/// different files. The mime type is the collection discriminator available in
/// this table; MigrationV18 replaces the original id-only index with this one.
class MigrationV16 {
  final AppDatabase db;

  new(this.db);

  /// Tables whose primary key *is* the entry id.
  static const _idKeyedTables = ['dateTaken', 'metadata', 'address', 'favourites', 'trash', 'videoPlayback'];

  Future<void> run(Migrator m) async {
    // A database built by a test or an older chain can carry only the tables its
    // own version introduced; there is nothing to merge then.
    if (!await _tableExists('entry')) return;
    await _mergeDuplicateContentIds();
    await createNewIndexes(db);
  }

  Future<bool> _tableExists(String table) async {
    final rows = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", variables: [Variable.withString(table)]).get();
    return rows.isNotEmpty;
  }

  static Future<void> createNewIndexes(AppDatabase db) async {
    await db.customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_entry_media_store_identity ON entry (contentId, sourceMimeType) '
      'WHERE contentId IS NOT NULL AND sourceMimeType IS NOT NULL AND origin = ${EntryOrigins.mediaStoreContent}',
    );
  }

  /// Keeps the lowest id of each media-store identity and moves everything that
  /// referenced the dropped rows over to it.
  Future<void> _mergeDuplicateContentIds() async {
    final groups = await db.customSelect(
      'SELECT contentId, sourceMimeType, MIN(id) AS keepId FROM entry '
      'WHERE contentId IS NOT NULL AND sourceMimeType IS NOT NULL AND origin = ? '
      'GROUP BY contentId, sourceMimeType HAVING COUNT(*) > 1',
      variables: [Variable.withInt(EntryOrigins.mediaStoreContent)],
    ).get();
    for (final group in groups) {
      final contentId = group.data['contentId'] as int;
      final mimeType = group.data['sourceMimeType'] as String;
      final keepId = group.data['keepId'] as int;
      final droppedRows = await db.customSelect(
        'SELECT id FROM entry WHERE contentId = ? AND sourceMimeType = ? AND origin = ? AND id != ?',
        variables: [
          Variable.withInt(contentId),
          Variable.withString(mimeType),
          Variable.withInt(EntryOrigins.mediaStoreContent),
          Variable.withInt(keepId),
        ],
      ).get();
      final droppedIds = [for (final row in droppedRows) row.data['id'] as int];
      if (droppedIds.isEmpty) continue;
      for (final id in droppedIds) {
        for (final table in _idKeyedTables) {
          // The survivor may already hold a row here (e.g. a rating read from
          // the file), in which case its own row wins and the other is left
          // for the delete below.
          await db.customStatement('UPDATE OR IGNORE $table SET id = ? WHERE id = ?', [keepId, id]);
          await db.customStatement('DELETE FROM $table WHERE id = ?', [id]);
        }
        await db.customStatement('UPDATE covers SET entryId = ? WHERE entryId = ?', [keepId, id]);
        // A stack tile pointing at a dropped row would hide the survivor
        // behind a row that no longer exists.
        await db.customStatement('UPDATE entry SET stackTileId = ? WHERE stackTileId = ?', [keepId, id]);
      }
      await db.customStatement(
        'DELETE FROM entry WHERE contentId = ? AND sourceMimeType = ? AND origin = ? AND id != ?',
        [contentId, mimeType, EntryOrigins.mediaStoreContent, keepId],
      );
    }
  }
}
