import 'dart:convert';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
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

  /// AppMeta key of the ordering before each group owned one.
  ///
  /// Only the v11 migration reads it, to seed the per-group column; nothing writes
  /// it any more.
  static const keyLegacyOrdering = 'wallpaper.groupedOrdering';

  /// AppMeta key of the notification bar switch.
  ///
  /// It is the user's answer to "may this wallpaper keep a notification around":
  /// off means the service posts nothing and never promotes itself to a
  /// foreground service, not a hidden bar.
  static const keyNotification = 'wallpaper.groupedNotification';

  /// AppMeta key of the home-screen scroll effect switch.
  ///
  /// It is global to the grouped wallpaper: it changes how every group is baked,
  /// so it never belongs to a group row and never bumps `updatedAt`.
  static const keyScrollEffect = 'wallpaper.groupedScrollEffect';

  /// AppMeta key of how many photos the usage history keeps.
  ///
  /// Global like the switches above: the history spans every group, so its size
  /// is a property of the wallpaper, not of one group. `0` turns recording off
  /// without deleting what was already recorded.
  static const keyHistoryLimit = 'wallpaper.groupedHistoryLimit';

  /// AppMeta key of how the grouped wallpaper's bottom-bar entry is placed.
  ///
  /// The entry is derived at build time rather than written into the user's
  /// `bottomNavigationActions`, so its placement needs a home of its own.
  static const keyNavMode = 'wallpaper.groupedNavMode';

  /// AppMeta key of the user closing the derived bottom-bar entry.
  static const keyNavEntryClosed = 'wallpaper.groupedNavEntryClosed';

  /// AppMeta key of "do not ask before clearing the whole usage history".
  ///
  /// Clearing is all-or-nothing, so the confirmation dialog is the only guard.
  /// A user who is sure can turn it off, and the history page's menu keeps a
  /// checked "confirm before clearing" entry to turn it back on: the dialog
  /// cannot offer that once it is skipped.
  static const keyHistoryClearSkipConfirm = 'wallpaper.groupedHistoryClearSkipConfirm';

  /// AppMeta key of "the grouped wallpaper has been the system wallpaper".
  ///
  /// Another wallpaper replacing it looks exactly like a wallpaper the user never
  /// set, so this marker is what tells the two apart when the page warns about an
  /// external replacement. It is cleared once the warning is shown.
  static const keyWasActive = 'wallpaper.groupedWasActive';

  /// AppMeta key of "do not warn about another wallpaper replacing this one".
  static const keyOverwriteDismissed = 'wallpaper.groupedOverwriteDismissed';

  final AppDatabase db;

  new(this.db);

  /// Groups in display order; the number is derived from that order.
  ///
  /// A group written before the scroll switch moved into its effects reads the
  /// old app-wide value, so an upgrade never silently changes how the wallpaper
  /// pans.
  Future<List<WallpaperGroup>> loadGroups() async {
    final query = db.select(db.wallpaperGroupRows)..orderBy([(t) => OrderingTerm.asc(t.position)]);
    final rows = await query.get();
    final legacyScrollEffect = await readScrollEffect();
    return [
      for (var i = 0; i < rows.length; i++) _toGroup(rows[i], i + 1, legacyScrollEffect: legacyScrollEffect),
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
                effects: Value(jsonEncode(group.effects.toJsonMap())),
                interval: Value(group.interval.seconds),
                ordering: Value(group.ordering.name),
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

  /// Writes one group's auto-advance contract.
  ///
  /// The contract belongs to the group, not the app: each group keeps its own
  /// interval and ordering, so a private group can stay still while a public one
  /// rotates. The values only affect future picks, so writing them does not bump
  /// `updatedAt` (which would re-bake the frame on screen).
  Future<void> writeAutoAdvance(String id, {WallpaperInterval? interval, GroupedWallpaperOrdering? ordering}) async {
    if (interval == null && ordering == null) return;
    await (db.update(db.wallpaperGroupRows)..where((t) => t.id.equals(id))).write(
      WallpaperGroupRowsCompanion(
        interval: interval == null ? const Value.absent() : Value(interval.seconds),
        ordering: ordering == null ? const Value.absent() : Value(ordering.name),
      ),
    );
  }

  /// Whether the wallpaper may show its notification bar.
  Future<bool> readNotification() async {
    final values = await AppMetaStore(db).read({keyNotification});
    return values[keyNotification] != 'false';
  }

  Future<void> writeNotification(bool enabled) => AppMetaStore(db).write({keyNotification: enabled ? 'true' : 'false'});

  /// Whether frames keep the photo's whole width for the launcher to pan.
  ///
  /// On by default, like the static wallpaper's scroll effect: a file without the
  /// value is a fresh install.
  Future<bool> readScrollEffect() async {
    final values = await AppMetaStore(db).read({keyScrollEffect});
    return values[keyScrollEffect] != 'false';
  }

  Future<void> writeScrollEffect(bool enabled) => AppMetaStore(db).write({keyScrollEffect: enabled ? 'true' : 'false'});

  /// How many photos the usage history keeps.
  ///
  /// A missing value is a fresh install (or a build before the history existed),
  /// which starts at [GroupedWallpaperHistoryLimit.defaultLimit]. The stored value
  /// is clamped on read, so a corrupted row cannot disable the history page or
  /// grow it without bound.
  Future<int> readHistoryLimit() async {
    final values = await AppMetaStore(db).read({keyHistoryLimit});
    final parsed = int.tryParse(values[keyHistoryLimit] ?? '');
    return GroupedWallpaperHistoryLimit.sanitize(parsed ?? GroupedWallpaperHistoryLimit.defaultLimit);
  }

  /// Stores the history limit without touching the recorded rows.
  ///
  /// Lowering the limit only changes what the next shown photo prunes, exactly as
  /// the user asked: changing a number must never delete history on its own.
  Future<void> writeHistoryLimit(int limit) => AppMetaStore(db).write({keyHistoryLimit: '${GroupedWallpaperHistoryLimit.sanitize(limit)}'});

  /// Whether clearing the usage history skips its confirmation dialog.
  Future<bool> readHistoryClearSkipConfirm() async {
    final values = await AppMetaStore(db).read({keyHistoryClearSkipConfirm});
    return values[keyHistoryClearSkipConfirm] == 'true';
  }

  Future<void> writeHistoryClearSkipConfirm(bool skip) => AppMetaStore(db).write({keyHistoryClearSkipConfirm: skip ? 'true' : 'false'});

  /// How the grouped wallpaper's bottom-bar entry is placed.
  Future<GroupedWallpaperNavMode> readNavMode() async {
    final values = await AppMetaStore(db).read({keyNavMode});
    return groupedWallpaperNavModeFrom(values[keyNavMode]);
  }

  Future<void> writeNavMode(GroupedWallpaperNavMode mode) => AppMetaStore(db).write({keyNavMode: mode.name});

  /// Whether the user closed the derived bottom-bar entry.
  Future<bool> readNavEntryClosed() async {
    final values = await AppMetaStore(db).read({keyNavEntryClosed});
    return values[keyNavEntryClosed] == 'true';
  }

  Future<void> writeNavEntryClosed(bool closed) => AppMetaStore(db).write({keyNavEntryClosed: closed ? 'true' : 'false'});

  /// Whether the grouped wallpaper has already been the system wallpaper.
  Future<bool> readWasActive() async {
    final values = await AppMetaStore(db).read({keyWasActive});
    return values[keyWasActive] == 'true';
  }

  Future<void> writeWasActive(bool active) => AppMetaStore(db).write({keyWasActive: active ? 'true' : 'false'});

  /// Whether the user asked not to be warned about an external replacement.
  Future<bool> readOverwriteDismissed() async {
    final values = await AppMetaStore(db).read({keyOverwriteDismissed});
    return values[keyOverwriteDismissed] == 'true';
  }

  Future<void> writeOverwriteDismissed(bool dismissed) => AppMetaStore(db).write({keyOverwriteDismissed: dismissed ? 'true' : 'false'});

  /// Writes one group's effects and bumps its `updatedAt` so the next bake sees
  /// the change.
  ///
  /// This deliberately bypasses the page's draft: the effects page applies as the
  /// sliders move, like Muzei, while range edits still wait for "save changes".
  Future<void> writeEffects(String id, WallpaperEffectsConfig effects, {required int updatedAt}) => writeEffectsFor({id}, effects, updatedAt: updatedAt);

  /// Copies [effects] to every group in [ids] in one transaction.
  Future<void> writeEffectsFor(Set<String> ids, WallpaperEffectsConfig effects, {required int updatedAt}) async {
    if (ids.isEmpty) return;
    final encoded = jsonEncode(effects.toJsonMap());
    await db.transaction(() async {
      for (final id in ids) {
        await (db.update(db.wallpaperGroupRows)..where((t) => t.id.equals(id))).write(
          WallpaperGroupRowsCompanion(
            effects: Value(encoded),
            updatedAt: Value(updatedAt),
          ),
        );
      }
    });
  }

  static WallpaperGroup _toGroup(WallpaperGroupRow row, int number, {required bool legacyScrollEffect}) => WallpaperGroup(
        id: row.id,
        number: number,
        name: row.name,
        description: row.description,
        enabled: row.enabled,
        current: row.current,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        effects: _effects(row.effects, legacyScrollEffect: legacyScrollEffect),
        interval: WallpaperInterval.tryFromSeconds(row.interval) ?? WallpaperInterval.never,
        ordering: GroupedWallpaperOrdering.tryParse(row.ordering),
      );

  /// Parses the stored effects, falling back to identity when the value is from a
  /// newer build or was truncated.
  static WallpaperEffectsConfig _effects(String raw, {required bool legacyScrollEffect}) {
    if (raw.isEmpty) return WallpaperEffectsConfig(homeScrollEffect: legacyScrollEffect);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return WallpaperEffectsConfig.fromJsonMap(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
          legacyScrollEffect: legacyScrollEffect,
        );
      }
    } catch (_) {
      // A corrupt value must not cost the user their wallpaper.
    }
    return WallpaperEffectsConfig(homeScrollEffect: legacyScrollEffect);
  }
}
