import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_layout.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_auto_advance.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The saved group the wallpaper draws from.
///
/// It is read from the database, never from the page's in-memory draft: the live
/// wallpaper must keep showing the saved state until the user saves.
@immutable
class GroupedWallpaperPlan extends Equatable {
  final WallpaperGroup group;

  /// The group's saved range; null for group 0, which narrows nothing.
  final VisibleRange? range;

  /// Whether the grouped wallpaper was explicitly turned off.
  ///
  /// Disabling keeps the last frame on screen and stops following the group; it
  /// never changes the wallpaper the system is showing.
  final bool disabled;

  /// The gestures the renderer acts on, global to both wallpapers.
  final GroupedWallpaperGestures gestures;

  /// How the next photo is chosen within the group.
  final GroupedWallpaperOrdering ordering;

  /// How often the group moves to its next photo; `never` leaves it still.
  final WallpaperInterval interval;

  /// Whether the wallpaper is frozen and keeps the current photo.
  final bool paused;

  /// Whether the wallpaper may show its notification bar.
  final bool notification;

  /// Whether frames keep the photo's whole width for the launcher to pan.
  ///
  /// Global to the grouped wallpaper: the page has one switch, not one per group.
  final bool scrollEffect;

  const new({
    required this.group,
    this.range,
    this.disabled = false,
    this.gestures = const GroupedWallpaperGestures(),
    this.ordering = GroupedWallpaperOrdering.defaultOrdering,
    this.interval = WallpaperInterval.never,
    this.paused = false,
    this.notification = true,
    this.scrollEffect = true,
  });

  bool get isNone => group.isNone;

  bool get locked => range?.locked ?? false;

  /// The group's home/lock effects, applied to every slot this plan bakes.
  WallpaperEffectsConfig get effects => group.effects;

  /// Whether a frame should follow [group] right now.
  bool get enabled => !disabled && !group.isNone;

  @override
  List<Object?> get props => [group, range, disabled, gestures, ordering, interval, paused, notification, scrollEffect];
}

/// Reads and updates [GroupedWallpaperPlan].
abstract interface class GroupedWallpaperPlanStore {
  Future<GroupedWallpaperPlan> load();

  /// Makes the first enabled group current and turns the feature back on.
  ///
  /// This is the "activation with no group selected" rule: turning the grouped
  /// wallpaper on must never leave the placeholder, so it lands on the first
  /// enabled group instead. With no enabled group the feature stays off.
  Future<GroupedWallpaperPlan> adoptFirstEnabledGroup();

  /// Records the explicit off/on switch without touching the current group.
  Future<void> setDisabled(bool disabled);

  /// Stores the gesture bindings, which are global to both wallpapers.
  Future<void> setGestures(GroupedWallpaperGestures gestures);

  /// Freezes or resumes the wallpaper without changing the current group.
  Future<void> setPaused(bool paused);

  /// Records whether the wallpaper may show its notification bar.
  Future<void> setNotification(bool enabled);

  /// Records whether frames keep the photo's whole width for the launcher to pan.
  Future<void> setScrollEffect(bool enabled);

  /// Makes the next (`delta > 0`) or previous enabled group current.
  ///
  /// Group 0 is not part of the rotation: from it, "next" starts at the first
  /// enabled group and "previous" at the last. Switching also resumes a frozen
  /// wallpaper, because the user is asking to see another group.
  Future<GroupedWallpaperPlan> switchGroup(int delta);
}

/// Reads the plan from the app database.
///
/// The page keeps a draft of the groups and ranges; the wallpaper deliberately
/// bypasses it and reads the committed rows, so an unsaved edit cannot change
/// what is on the home screen.
class SavedGroupedWallpaperPlanStore implements GroupedWallpaperPlanStore {
  final AppDatabaseProvider? provider;

  new({this.provider});

  Future<AppDatabase> _open() async => await (provider ?? getIt<AppDatabaseProvider>()).open();

  @override
  Future<GroupedWallpaperPlan> load() async {
    final db = await _open();
    final store = WallpaperGroupStore(db);
    final groups = normalizeWallpaperGroups(await store.loadGroups());
    final disabled = await store.readDisabled();
    final gestures = await store.readGestures();
    final paused = await store.readPaused();
    final notification = await store.readNotification();
    final scrollEffect = await store.readScrollEffect();
    final group = groups.firstWhereOrNull((candidate) => candidate.current && candidate.enabled) ?? WallpaperGroup.none;
    if (group.isNone) {
      return GroupedWallpaperPlan(
        group: group,
        disabled: disabled,
        gestures: gestures,
        ordering: group.ordering,
        interval: group.interval,
        paused: paused,
        notification: notification,
        scrollEffect: scrollEffect,
      );
    }
    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: group.id);
    return GroupedWallpaperPlan(
      group: group,
      range: range,
      disabled: disabled,
      gestures: gestures,
      ordering: group.ordering,
      interval: group.interval,
      paused: paused,
      notification: notification,
      scrollEffect: scrollEffect,
    );
  }

  @override
  Future<GroupedWallpaperPlan> adoptFirstEnabledGroup() async {
    final db = await _open();
    final store = WallpaperGroupStore(db);
    final groups = normalizeWallpaperGroups(await store.loadGroups());
    final gestures = await store.readGestures();
    final notification = await store.readNotification();
    final scrollEffect = await store.readScrollEffect();
    // A group that is already current is the answer: adopting is idempotent, so
    // a repeated activation never moves the wallpaper to another group.
    final group = groups.firstWhereOrNull((candidate) => candidate.current && candidate.enabled) ?? enabledWallpaperGroups(groups).firstOrNull;
    if (group == null) {
      await store.writeDisabled(true);
      return GroupedWallpaperPlan(group: WallpaperGroup.none, disabled: true, gestures: gestures, notification: notification, scrollEffect: scrollEffect);
    }
    if (!group.current) {
      await store.saveGroups(normalizeWallpaperGroups([
        for (final candidate in groups) candidate.copyWith(current: candidate.id == group.id),
      ]));
    }
    await store.writeDisabled(false);
    // Activation is the user turning the wallpaper on, so a freeze from the
    // previous session must not keep the new frame from appearing.
    await store.writePaused(false);
    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: group.id);
    return GroupedWallpaperPlan(
      group: group.copyWith(current: true),
      range: range,
      gestures: gestures,
      ordering: group.ordering,
      interval: group.interval,
      notification: notification,
      scrollEffect: scrollEffect,
    );
  }

  @override
  Future<void> setDisabled(bool disabled) async => WallpaperGroupStore(await _open()).writeDisabled(disabled);

  @override
  Future<void> setGestures(GroupedWallpaperGestures gestures) async => WallpaperGroupStore(await _open()).writeGestures(gestures);

  @override
  Future<void> setPaused(bool paused) async => WallpaperGroupStore(await _open()).writePaused(paused);

  @override
  Future<void> setNotification(bool enabled) async => WallpaperGroupStore(await _open()).writeNotification(enabled);

  @override
  Future<void> setScrollEffect(bool enabled) async => WallpaperGroupStore(await _open()).writeScrollEffect(enabled);

  @override
  Future<GroupedWallpaperPlan> switchGroup(int delta) async {
    final db = await _open();
    final store = WallpaperGroupStore(db);
    final groups = normalizeWallpaperGroups(await store.loadGroups());
    final enabled = enabledWallpaperGroups(groups);
    if (enabled.isEmpty) return load();
    final currentId = currentWallpaperGroupId(groups);
    final index = enabled.indexWhere((group) => group.id == currentId);
    // From group 0, "next" enters at the first group and "previous" at the last.
    final start = index >= 0 ? index : (delta > 0 ? -1 : 0);
    final target = enabled[((start + delta) % enabled.length + enabled.length) % enabled.length];
    await store.saveGroups(normalizeWallpaperGroups([
      for (final group in groups) group.copyWith(current: group.id == target.id),
    ]));
    await store.writePaused(false);
    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: target.id);
    return GroupedWallpaperPlan(
      group: target.copyWith(current: true),
      range: range,
      disabled: await store.readDisabled(),
      gestures: await store.readGestures(),
      ordering: target.ordering,
      interval: target.interval,
      notification: await store.readNotification(),
      scrollEffect: await store.readScrollEffect(),
    );
  }
}
