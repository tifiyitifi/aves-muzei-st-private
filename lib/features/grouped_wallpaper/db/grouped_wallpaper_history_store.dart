import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_entry.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:drift/drift.dart';

/// Persistence of the grouped wallpaper's usage history.
///
/// The history is written by the engine every time the photo on screen changes,
/// so the hot path is one upsert plus one prune in a transaction. Recording is
/// best-effort: the caller logs a failure instead of letting it cost the user
/// their wallpaper.
class GroupedWallpaperHistoryStore {
  final AppDatabase db;

  new(this.db);

  /// Records that [entryId] was shown in [groupId] at [usedAt].
  ///
  /// The photo is de-duplicated per group: showing it again only moves it to the
  /// front. After the write, the oldest rows beyond [limit] are dropped, so a
  /// lowered limit takes effect on the next shown photo rather than deleting
  /// anything now.
  Future<void> record({
    required int entryId,
    required String groupId,
    required String groupName,
    required int groupNumber,
    required int usedAt,
    required int limit,
  }) async {
    if (entryId <= 0) return;
    final max = GroupedWallpaperHistoryLimit.sanitize(limit);
    if (max <= 0) return;
    await db.transaction(() async {
      final updated = await (db.update(db.groupedWallpaperHistoryRows)..where((t) => t.entryId.equals(entryId) & t.groupId.equals(groupId))).write(
        GroupedWallpaperHistoryRowsCompanion(
          groupName: Value(groupName),
          groupNumber: Value(groupNumber),
          usedAt: Value(usedAt),
        ),
      );
      if (updated == 0) {
        await db.into(db.groupedWallpaperHistoryRows).insert(
              GroupedWallpaperHistoryRowsCompanion.insert(
                entryId: entryId,
                groupId: groupId,
                usedAt: usedAt,
                groupName: Value(groupName),
                groupNumber: Value(groupNumber),
              ),
            );
      }
      // Keep the newest `max` rows. `id` breaks ties so two photos shown in the
      // same millisecond still prune deterministically.
      await db.customStatement(
        'DELETE FROM grouped_wallpaper_history WHERE id NOT IN ('
        'SELECT id FROM grouped_wallpaper_history ORDER BY usedAt DESC, id DESC LIMIT ?)',
        [max],
      );
    });
  }

  /// The recorded photos, newest first.
  ///
  /// [groupId] narrows the list to one group, which is what the history page
  /// shows when the user came from a group; `null` means every group.
  Future<List<GroupedWallpaperHistoryEntry>> load({String? groupId}) async {
    final query = db.select(db.groupedWallpaperHistoryRows)
      ..orderBy([
        (t) => OrderingTerm.desc(t.usedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    if (groupId != null) query.where((t) => t.groupId.equals(groupId));
    return [for (final row in await query.get()) _toEntry(row)];
  }

  Future<int> count({String? groupId}) async {
    final count = db.groupedWallpaperHistoryRows.id.count();
    final query = db.selectOnly(db.groupedWallpaperHistoryRows)..addColumns([count]);
    if (groupId != null) query.where(db.groupedWallpaperHistoryRows.groupId.equals(groupId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Deletes the records of [groupId], or every group when it is null.
  Future<void> clear({String? groupId}) {
    final query = db.delete(db.groupedWallpaperHistoryRows);
    if (groupId != null) query.where((t) => t.groupId.equals(groupId));
    return query.go();
  }

  static GroupedWallpaperHistoryEntry _toEntry(GroupedWallpaperHistoryRow row) => GroupedWallpaperHistoryEntry(
        entryId: row.entryId,
        groupId: row.groupId,
        groupName: row.groupName,
        groupNumber: row.groupNumber,
        usedAt: row.usedAt,
      );
}
