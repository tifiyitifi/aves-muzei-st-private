import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_entry.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
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

  /// Records that [entryId] was shown in [groupId] on [surface] at [usedAt].
  ///
  /// The photo is de-duplicated per group and surface: showing it again only
  /// moves it to the front. After the write, the oldest rows beyond [limit] are
  /// dropped, so a lowered limit takes effect on the next shown photo rather
  /// than deleting anything now.
  Future<void> record({
    required int entryId,
    required String groupId,
    required String groupName,
    required int groupNumber,
    required int usedAt,
    required int limit,
    required WallpaperSurface surface,
  }) async {
    if (entryId <= 0) return;
    final max = GroupedWallpaperHistoryLimit.sanitize(limit);
    if (max <= 0) return;
    await db.transaction(() async {
      // One atomic upsert on the (entryId, groupId, surface) key. A read-then-
      // write would let the UI and the background isolate both see "no row" and
      // make one of them fail its insert on the unique constraint.
      await db.into(db.groupedWallpaperHistoryRows).insert(
            GroupedWallpaperHistoryRowsCompanion.insert(
              entryId: entryId,
              groupId: groupId,
              usedAt: usedAt,
              groupName: Value(groupName),
              groupNumber: Value(groupNumber),
              surface: Value(surface.name),
            ),
            onConflict: DoUpdate(
              (old) => GroupedWallpaperHistoryRowsCompanion(
                groupName: Value(groupName),
                groupNumber: Value(groupNumber),
                usedAt: Value(usedAt),
              ),
              // The row is de-duplicated by this key, not by the autoincrement
              // id, so the conflict target has to name it.
              target: [
                db.groupedWallpaperHistoryRows.entryId,
                db.groupedWallpaperHistoryRows.groupId,
                db.groupedWallpaperHistoryRows.surface,
              ],
            ),
          );
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
  /// shows when the user came from a group; `null` means every group. [surface]
  /// narrows it to one surface for the page's home/lock scope; `null` means both.
  /// [limit] caps the read, which is all a "previous lock photo" lookup needs.
  Future<List<GroupedWallpaperHistoryEntry>> load({String? groupId, WallpaperSurface? surface, int? limit}) async {
    final query = db.select(db.groupedWallpaperHistoryRows)
      ..orderBy([
        (t) => OrderingTerm.desc(t.usedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    if (groupId != null) query.where((t) => t.groupId.equals(groupId));
    if (surface != null) query.where((t) => t.surface.equals(surface.name));
    if (limit != null && limit > 0) query.limit(limit);
    return [for (final row in await query.get()) _toEntry(row)];
  }

  Future<int> count({String? groupId, WallpaperSurface? surface}) async {
    final count = db.groupedWallpaperHistoryRows.id.count();
    final query = db.selectOnly(db.groupedWallpaperHistoryRows)..addColumns([count]);
    if (groupId != null) query.where(db.groupedWallpaperHistoryRows.groupId.equals(groupId));
    if (surface != null) query.where(db.groupedWallpaperHistoryRows.surface.equals(surface.name));
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
        surface: WallpaperSurface.parse(row.surface),
        usedAt: row.usedAt,
      );
}
