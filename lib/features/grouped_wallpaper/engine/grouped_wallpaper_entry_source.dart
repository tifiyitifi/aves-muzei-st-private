import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The images a group may draw from, newest first, plus the group's total.
@immutable
class GroupedWallpaperEntryWindow extends Equatable {
  /// How many images the group resolves to, not just the ones loaded here.
  final int count;
  final List<AvesEntry> entries;

  const new({required this.count, required this.entries});

  static const empty = GroupedWallpaperEntryWindow(count: 0, entries: []);

  @override
  List<Object?> get props => [count, entries];
}

/// Loads the media set the wallpaper may use.
abstract interface class GroupedWallpaperEntrySource {
  Future<GroupedWallpaperEntryWindow> load(VisibleRange? range, {required int limit});
}

/// Queries the app database for a group's images.
///
/// The wallpaper media set is every image AND the group's range (group 0 narrows
/// nothing), with the user's hidden filters and locked vaults excluded exactly
/// like the gallery excludes them. Videos never take part.
class GroupedWallpaperDbEntrySource implements GroupedWallpaperEntrySource {
  /// How many newest images to load: enough to skip the one already on screen
  /// and any whose file disappeared since the last scan.
  static const int scanLimit = 32;

  final LocalMediaDb? database;

  new({this.database});

  @override
  Future<GroupedWallpaperEntryWindow> load(VisibleRange? range, {required int limit}) async {
    final db = database ?? localMediaDb;
    await db.init();
    final filter = wallpaperMediaSetFilter(range);
    final predicate = predicateForFilters(
      {?filter},
      hidden: settings.hiddenFilters,
      lockedVaultDirs: vaults.vaultDirectories.where(vaults.isLocked).toSet(),
    );
    if (predicate == null) return GroupedWallpaperEntryWindow.empty;
    final count = await db.countEntries(predicate);
    if (count == 0) return GroupedWallpaperEntryWindow.empty;
    final entries = await db.loadEntryWindow(
      predicate: predicate,
      sort: SortFactor.date,
      reverse: false,
      limit: limit,
      offset: 0,
    );
    return GroupedWallpaperEntryWindow(count: count, entries: entries);
  }
}

/// Picks the next image to show.
///
/// Newest first, skipping the entry already on screen so a sync visibly changes
/// the wallpaper; entries whose file disappeared since the last scan are skipped
/// too. When nothing else is usable the previous image is returned rather than
/// blanking the screen.
AvesEntry? selectGroupedWallpaperEntry(Iterable<AvesEntry> entries, {int? previousEntryId}) {
  AvesEntry? usable;
  for (final entry in entries) {
    if (entry.isMissingAtPath) continue;
    usable ??= entry;
    if (entry.id != previousEntryId) return entry;
  }
  return usable;
}
