import 'dart:convert';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:drift/drift.dart';

/// Persistence for wallpaper groups.
///
/// Each group owns one `wallpaper`-scope visible range; the range itself stays
/// owned by [VisibleRangeStore], and only the cascade on deletion lives here so
/// a group can never leave its range behind.
class WallpaperGroupStore {
  /// AppMeta key of the bundled defaults version already applied. `AppMetaStore`
  /// is the fork's generic bookkeeping table, so this feature needs no table of
  /// its own just for one marker.
  static const keyDefaultsVersion = 'wallpaper.defaultsVersion';

  /// AppMeta key of the explicit "the grouped wallpaper is off" switch.
  ///
  /// It is deliberately separate from the `current` flag: disabling keeps the
  /// group that was playing so turning the feature back on returns to it, and it
  /// has to survive a reboot, where the wallpaper service starts again and would
  /// otherwise mistake the restart for a fresh activation.
  static const keyDisabled = 'wallpaper.groupedDisabled';

  /// AppMeta key of the gesture bindings, which are global to both wallpapers.
  static const keyGestures = 'wallpaper.groupedGestures';

  /// AppMeta key of the ordering, global until each group owns one.
  static const keyOrdering = 'wallpaper.groupedOrdering';

  final AppDatabase db;

  new(this.db);

  /// Groups in display order; the number is derived from that order.
  Future<List<WallpaperGroup>> loadGroups() async {
    final query = db.select(db.wallpaperGroupRows)..orderBy([(t) => OrderingTerm.asc(t.position)]);
    final rows = await query.get();
    return [
      for (var i = 0; i < rows.length; i++) _toGroup(rows[i], i + 1),
    ];
  }

  /// Writes the whole list in one transaction.
  ///
  /// The controller always owns the complete list, so a single writer keeps the
  /// stored order, the derived numbers and the single `current` flag consistent.
  /// Rows outside the list are left alone: deletion is explicit.
  Future<void> saveGroups(Iterable<WallpaperGroup> groups) async {
    final list = groups.toList();
    await db.transaction(() async {
      for (var i = 0; i < list.length; i++) {
        final group = list[i];
        await db.into(db.wallpaperGroupRows).insertOnConflictUpdate(
              WallpaperGroupRowsCompanion.insert(
                id: group.id,
                createdAt: group.createdAt,
                updatedAt: group.updatedAt,
                name: Value(group.name),
                description: Value(group.description),
                enabled: Value(group.enabled),
                current: Value(group.current),
                position: Value(i),
              ),
            );
      }
    });
  }

  /// Deletes a group together with its visible range and applied-rule targets.
  Future<void> deleteGroup(String id) async {
    await db.transaction(() async {
      await (db.delete(db.wallpaperGroupRows)..where((t) => t.id.equals(id))).go();
      await VisibleRangeStore(db).deleteRange(wallpaperGroupRangeId(id));
    });
  }

  Future<int> readDefaultsVersion() async {
    final values = await AppMetaStore(db).read({keyDefaultsVersion});
    return int.tryParse(values[keyDefaultsVersion] ?? '') ?? 0;
  }

  Future<void> writeDefaultsVersion(int version) => AppMetaStore(db).write({keyDefaultsVersion: '$version'});

  /// Whether the grouped wallpaper was explicitly turned off.
  Future<bool> readDisabled() async {
    final values = await AppMetaStore(db).read({keyDisabled});
    return values[keyDisabled] == 'true';
  }

  Future<void> writeDisabled(bool disabled) => AppMetaStore(db).write({keyDisabled: disabled ? 'true' : 'false'});

  /// The gestures the wallpaper recognises, global to both wallpapers.
  Future<GroupedWallpaperGestures> readGestures() async {
    final values = await AppMetaStore(db).read({keyGestures});
    return GroupedWallpaperGestures.fromJsonString(values[keyGestures]);
  }

  Future<void> writeGestures(GroupedWallpaperGestures gestures) => AppMetaStore(db).write({keyGestures: jsonEncode(gestures.toJsonMap())});

  /// The ordering the next photo is chosen with.
  Future<GroupedWallpaperOrdering> readOrdering() async {
    final values = await AppMetaStore(db).read({keyOrdering});
    return GroupedWallpaperOrdering.tryParse(values[keyOrdering]);
  }

  Future<void> writeOrdering(GroupedWallpaperOrdering ordering) => AppMetaStore(db).write({keyOrdering: ordering.name});

  static WallpaperGroup _toGroup(WallpaperGroupRow row, int number) => WallpaperGroup(
        id: row.id,
        number: number,
        name: row.name,
        description: row.description,
        enabled: row.enabled,
        current: row.current,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
