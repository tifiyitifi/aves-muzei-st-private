import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The photo chosen for one slot, plus where it sits in the group.
///
/// [offset] is `-1` when the ordering does not walk a position (a "new photo"
/// pick), and the in-order cursor is only advanced by real offsets.
@immutable
class GroupedWallpaperPick extends Equatable {
  final AvesEntry? entry;

  /// How many images the group resolves to, not just the ones scanned here.
  final int total;
  final int offset;

  const new({this.entry, required this.total, this.offset = -1});

  const new empty() : entry = null, total = 0, offset = -1;

  bool get isEmpty => entry == null;

  @override
  List<Object?> get props => [entry, total, offset];
}

/// Loads the media set the wallpaper may use and picks from it.
///
/// The pick is a query, not a scan of a fixed window: the old "load the newest
/// 32 and walk them" approach could never leave that window, so a tap cycled
/// through a handful of photos. Each ordering now asks the database for the
/// position it needs, exactly like Muzei's source repository.
abstract interface class GroupedWallpaperEntrySource {
  /// How many images the group currently resolves to.
  Future<int> count(VisibleRange? range);

  /// The entry id above which a photo counts as "new" (Muzei's
  /// `maxLoadedArtworkId` seed).
  ///
  /// It is the highest id the app has handed out, not the newest photo by date:
  /// an edited or restored file keeps an old id while a newly imported one gets
  /// a higher id, which is the order the "new photos first" ordering relies on.
  Future<int> newPhotoMarker(VisibleRange? range);

  /// Picks the photo for the next slot.
  ///
  /// [cursor] is the in-order position remembered by the engine; it wraps around
  /// the group and is ignored by the other orderings. [attempt] is used by the
  /// bake retry loop, so a decode failure never retries the same photo.
  ///
  /// [newestEntryId] is the highest entry id shown so far (Muzei's
  /// `maxLoadedArtworkId`) and [excludeEntryIds] the queued photos plus the
  /// recently shown ones, so the random ordering does not repeat itself.
  Future<GroupedWallpaperPick> pick(
    VisibleRange? range, {
    required GroupedWallpaperOrdering ordering,
    required int cursor,
    int attempt = 0,
    int newestEntryId = 0,
    Set<int> excludeEntryIds = const {},
  });

  /// The entry with [id], or null when it was deleted or is no longer visible.
  ///
  /// "Previous photo" re-bakes an entry the state remembers, and that entry can
  /// have left the library in the meantime. It is checked against [range] again,
  /// so locking a vault or hiding a filter between two photos cannot make the
  /// wallpaper show a photo the user just hid.
  Future<AvesEntry?> entryById(VisibleRange? range, int id);
}

/// Queries the app database for a group's images.
///
/// The wallpaper media set is every image AND the group's range (group 0 narrows
/// nothing), with the user's hidden filters and locked vaults excluded exactly
/// like the gallery excludes them. Videos never take part.
class GroupedWallpaperDbEntrySource implements GroupedWallpaperEntrySource {
  /// How many random samples to try before accepting a recently shown photo.
  ///
  /// The exclusion set is the queue plus the recent list, so a few tries find a
  /// fresh photo in any group larger than that; a tiny group can exhaust it and
  /// must repeat.
  static const int maxRandomAttempts = 12;

  /// How many new entries to scan past an unusable one in a single pick.
  static const int maxNewScan = 8;

  final LocalMediaDb? database;

  /// Seeded in tests so random ordering stays reproducible.
  final Random _random;

  new({this.database, Random? random}) : _random = random ?? Random();

  LocalMediaDb get _db => database ?? localMediaDb;

  @override
  Future<int> count(VisibleRange? range) async {
    final predicate = _predicateFor(range);
    if (predicate == null) return 0;
    final db = _db;
    await db.init();
    return db.countEntries(predicate);
  }

  @override
  Future<int> newPhotoMarker(VisibleRange? range) async {
    final db = _db;
    await db.init();
    try {
      // The allocator's next id is above every id already handed out, so the id
      // before it is the high-water mark: a photo imported after this point gets
      // a higher id and is served first. The newest photo by date is not a
      // usable marker, because ids follow insertion, not the displayed date.
      return db.nextId - 1;
    } on StateError {
      // The allocator's block ran dry before its background top-up landed. A
      // marker is only an optimization; fall back to the newest photo.
      final predicate = _predicateFor(range);
      if (predicate == null) return 0;
      final rows = await db.loadEntryWindow(
        predicate: predicate,
        sort: SortFactor.date,
        reverse: false,
        limit: 1,
        offset: 0,
      );
      return rows.isEmpty ? 0 : rows.first.id;
    }
  }

  @override
  Future<GroupedWallpaperPick> pick(
    VisibleRange? range, {
    required GroupedWallpaperOrdering ordering,
    required int cursor,
    int attempt = 0,
    int newestEntryId = 0,
    Set<int> excludeEntryIds = const {},
  }) async {
    final predicate = _predicateFor(range);
    if (predicate == null) return const GroupedWallpaperPick.empty();
    final db = _db;
    await db.init();
    final total = await db.countEntries(predicate);
    if (total <= 0) return const GroupedWallpaperPick.empty();

    if (ordering == GroupedWallpaperOrdering.newThenRandom) {
      final fresh = await _pickNew(
        db,
        predicate,
        newestEntryId: newestEntryId,
        attempt: attempt,
        excludeEntryIds: excludeEntryIds,
      );
      if (fresh != null) return GroupedWallpaperPick(entry: fresh, total: total);
      // No new photos left: Muzei falls through to the random strategy.
    }

    if (ordering == GroupedWallpaperOrdering.inOrder) {
      final offset = _normalize(cursor + attempt, total);
      final entry = await _entryAt(db, predicate, offset);
      return GroupedWallpaperPick(entry: entry, total: total, offset: offset);
    }

    final randomPick = await _pickRandom(
      db,
      predicate,
      total: total,
      attempt: attempt,
      excludeEntryIds: excludeEntryIds,
    );
    if (randomPick == null) return GroupedWallpaperPick(total: total);
    return GroupedWallpaperPick(entry: randomPick.entry, total: total, offset: randomPick.offset);
  }

  @override
  Future<AvesEntry?> entryById(VisibleRange? range, int id) async {
    final predicate = _predicateFor(range);
    if (predicate == null) return null;
    final db = _db;
    await db.init();
    // Re-apply the whole media set, not just "the row still exists": a locked
    // vault or a hidden filter must win over a history entry.
    final scoped = CollectionWindowPredicate(
      conjunction: [
        ...predicate.conjunction,
        (sql: 'e.id = ?', variables: [Variable(id)], requires: const <WindowTable>{}),
      ],
      trashedOnly: predicate.trashedOnly,
    );
    if (await db.countEntries(scoped) <= 0) return null;
    final entries = await db.loadEntriesById({id});
    if (entries.isEmpty) return null;
    final entry = entries.first;
    return _isUsable(entry) ? entry : null;
  }

  /// One photo added after [newestEntryId], in id order.
  ///
  /// Entry ids are MediaStore ids, which grow with insertion, so walking forward
  /// from the last one shown is Muzei's `_id > maxLoadedArtworkId` step.
  Future<AvesEntry?> _pickNew(
    LocalMediaDb db,
    CollectionWindowPredicate predicate, {
    required int newestEntryId,
    required int attempt,
    required Set<int> excludeEntryIds,
  }) async {
    if (newestEntryId <= 0) return null;
    final rows = await db.loadWalkWindow(
      predicate: predicate,
      afterId: newestEntryId,
      limit: attempt + 1 + maxNewScan,
    );
    var position = 0;
    for (final entry in rows) {
      if (!_isUsable(entry) || excludeEntryIds.contains(entry.id)) continue;
      if (position++ < attempt) continue;
      return entry;
    }
    return null;
  }

  /// A random photo, avoiding the one on screen and the recently shown ones.
  ///
  /// Rejection sampling, like Muzei's shuffled sequence: the exclusion set is
  /// small, so a handful of tries is enough. A group barely larger than the set
  /// can exhaust the tries, and repeating is better than a blank wallpaper.
  Future<({AvesEntry entry, int offset})?> _pickRandom(
    LocalMediaDb db,
    CollectionWindowPredicate predicate, {
    required int total,
    required int attempt,
    required Set<int> excludeEntryIds,
  }) async {
    for (var i = 0; i < maxRandomAttempts; i++) {
      final offset = _normalize(_random.nextInt(total) + attempt + i, total);
      final entry = await _entryAt(db, predicate, offset);
      if (entry == null || excludeEntryIds.contains(entry.id)) continue;
      return (entry: entry, offset: offset);
    }
    final offset = _normalize(_random.nextInt(total) + attempt, total);
    final entry = await _entryAt(db, predicate, offset);
    return entry == null ? null : (entry: entry, offset: offset);
  }

  Future<AvesEntry?> _entryAt(LocalMediaDb db, CollectionWindowPredicate predicate, int offset) async {
    final rows = await db.loadEntryWindow(
      predicate: predicate,
      // The same ordering the collection views use, so an in-order walk
      // follows the library instead of an arbitrary database order.
      sort: SortFactor.date,
      reverse: false,
      limit: 1,
      offset: offset,
    );
    if (rows.isEmpty) return null;
    final entry = rows.first;
    // The predicate already enforces the filters; re-checking one row keeps the
    // wallpaper safe if the state changed between the count and the window.
    return _isUsable(entry) ? entry : null;
  }

  /// The SQL predicate of the group's media set.
  ///
  /// [wallpaperMediaSetFilter] always adds the image MIME filter, so a video can
  /// never leak into the wallpaper. Hidden filters and locked vaults are applied
  /// exactly like the browse views apply them.
  CollectionWindowPredicate? _predicateFor(VisibleRange? range) => predicateForFilters(
    {?wallpaperMediaSetFilter(range)},
    hidden: settings.hiddenFilters,
    lockedVaultDirs: vaults.vaultDirectories.where(vaults.isLocked).toSet(),
  );

  bool _isUsable(AvesEntry entry) => entry.isImage && !entry.trashed && !entry.isMissingAtPath;

  /// Wraps [value] into `[0, total)`, including negative cursors.
  static int _normalize(int value, int total) => ((value % total) + total) % total;
}
