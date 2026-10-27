import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_layout.dart';
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

  const new({required this.group, this.range});

  bool get isNone => group.isNone;

  bool get locked => range?.locked ?? false;

  @override
  List<Object?> get props => [group, range];
}

/// Reads [GroupedWallpaperPlan] from wherever the saved groups live.
abstract interface class GroupedWallpaperPlanLoader {
  Future<GroupedWallpaperPlan> load();
}

/// Reads the plan from the app database.
///
/// The page keeps a draft of the groups and ranges; the wallpaper deliberately
/// bypasses it and reads the committed rows, so an unsaved edit cannot change
/// what is on the home screen.
class SavedGroupedWallpaperPlanLoader implements GroupedWallpaperPlanLoader {
  final AppDatabaseProvider? provider;

  new({this.provider});

  @override
  Future<GroupedWallpaperPlan> load() async {
    final db = await (provider ?? getIt<AppDatabaseProvider>()).open();
    final groups = normalizeWallpaperGroups(await WallpaperGroupStore(db).loadGroups());
    final group = groups.firstWhereOrNull((candidate) => candidate.current && candidate.enabled) ?? WallpaperGroup.none;
    if (group.isNone) return GroupedWallpaperPlan(group: group);
    final range = await VisibleRangeStore(db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: group.id);
    return GroupedWallpaperPlan(group: group, range: range);
  }
}
