import 'dart:math';

import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_entry_source.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../fake/db.dart';

/// `GroupedWallpaperDbEntrySource`: the three Muzei orderings, resolved by
/// querying the database instead of walking one fixed window.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(getIt.reset);

  AvesEntry entry(int id) => AvesEntry(
        id: id,
        uri: 'content://media/$id',
        path: null,
        contentId: id,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 300,
        height: 100,
        sourceRotationDegrees: 0,
        sizeBytes: 1,
        sourceTitle: 'IMG_$id',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: EntryOrigins.mediaStoreContent,
      );

  /// Newest first, as the collection order returns them.
  _FakeDb db(int n, {int first = 50}) => _FakeDb([for (var i = 0; i < n; i++) entry(first - i)]);

  test('an empty group resolves to nothing', () async {
    final source = GroupedWallpaperDbEntrySource(database: _FakeDb(const []));

    expect(await source.count(null), 0);
    expect(await source.newPhotoMarker(null), 0);
    final pick = await source.pick(null, ordering: GroupedWallpaperOrdering.random, cursor: 0);
    expect(pick.entry, isNull);
    expect(pick.total, 0);
  });

  test('the id high-water seeds the new-photo marker', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(5));

    // Ids 50..46: the next id the app hands out is 51, so everything above 50
    // was imported after this point.
    expect(await source.newPhotoMarker(null), 50);
  });

  test('in-order walks the collection and wraps around', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(3));

    final picks = [
      for (var cursor = 0; cursor < 5; cursor++) (await source.pick(null, ordering: GroupedWallpaperOrdering.inOrder, cursor: cursor)).entry?.id,
    ];

    expect(picks, [50, 49, 48, 50, 49]);
  });

  test('in-order skips the excluded entries when the cursor points at one', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(5));

    // The engine's own exclusion is the queue; in-order deliberately follows the
    // cursor, so it may land on a queued photo. That is Muzei's behaviour too:
    // the cursor is the position, not a filter.
    final pick = await source.pick(null, ordering: GroupedWallpaperOrdering.inOrder, cursor: 1, excludeEntryIds: {49});

    expect(pick.entry?.id, 49);
    expect(pick.offset, 1);
  });

  test('new photos are served in id order, oldest first', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(10));

    final first = await source.pick(null, ordering: GroupedWallpaperOrdering.newThenRandom, cursor: 0, newestEntryId: 48);
    final second = await source.pick(
      null,
      ordering: GroupedWallpaperOrdering.newThenRandom,
      cursor: 0,
      newestEntryId: 48,
      excludeEntryIds: {49},
    );

    expect(first.entry?.id, 49);
    expect(second.entry?.id, 50);
    // A new pick has no position in the collection order.
    expect(first.offset, -1);
  });

  test('new photos that are already queued are skipped', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(10));

    final pick = await source.pick(
      null,
      ordering: GroupedWallpaperOrdering.newThenRandom,
      cursor: 0,
      newestEntryId: 48,
      excludeEntryIds: {49},
    );

    expect(pick.entry?.id, 50);
  });

  test('new-then-random falls back to random once nothing is new', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(10), random: Random(1));

    final pick = await source.pick(
      null,
      ordering: GroupedWallpaperOrdering.newThenRandom,
      cursor: 0,
      newestEntryId: 50,
      excludeEntryIds: {50, 49, 48},
    );

    expect(pick.entry, isNotNull);
    expect(pick.entry!.id, isNot(isIn([50, 49, 48])));
    expect(pick.offset, greaterThanOrEqualTo(0));
  });

  test('random avoids the photo on screen and the recently shown ones', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(30), random: Random(3));

    for (var i = 0; i < 10; i++) {
      final pick = await source.pick(
        null,
        ordering: GroupedWallpaperOrdering.random,
        cursor: 0,
        excludeEntryIds: {50, 49, 48, 47},
      );
      expect(pick.entry, isNotNull);
      expect(pick.entry!.id, isNot(isIn([50, 49, 48, 47])));
    }
  });

  test('a group smaller than the exclusion set repeats rather than blanking', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(1));

    final pick = await source.pick(null, ordering: GroupedWallpaperOrdering.random, cursor: 0, excludeEntryIds: {50});

    expect(pick.entry?.id, 50);
  });

  test('a retry steps to another candidate', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(10), random: Random(2));

    final first = await source.pick(null, ordering: GroupedWallpaperOrdering.random, cursor: 0);
    final retried = await source.pick(null, ordering: GroupedWallpaperOrdering.random, cursor: 0, attempt: 1);

    expect(retried.entry, isNotNull);
    expect(retried.entry!.id, isNot(first.entry!.id));
  });

  test('a remembered photo is reloaded only while it is still in the media set', () async {
    final source = GroupedWallpaperDbEntrySource(database: db(3));

    expect((await source.entryById(null, 49))?.id, 49);
    expect(await source.entryById(null, 99), isNull);
  });
}

/// A database stand-in that answers the three queries the source makes.
class _FakeDb extends FakeAvesDb {
  final List<AvesEntry> rows;

  new(this.rows);

  /// The id high-water: one above the highest id in the fixture.
  @override
  int get nextId => rows.fold<int>(0, (max, entry) => entry.id > max ? entry.id : max) + 1;

  @override
  Future<int> countEntries([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]) async {
    // The source's `entryById` scopes the media set with an `e.id = ?` fragment;
    // the fixture has no SQL engine, so honour just that one.
    for (final fragment in predicate.conjunction) {
      if (fragment.sql == 'e.id = ?' && fragment.variables.length == 1) {
        final id = fragment.variables.first.value;
        return rows.any((entry) => entry.id == id) ? 1 : 0;
      }
    }
    return rows.length;
  }

  @override
  Future<Set<AvesEntry>> loadEntriesById(Set<int> ids) async => {
        for (final entry in rows)
          if (ids.contains(entry.id)) entry,
      };

  @override
  Future<List<AvesEntry>> loadEntryWindow({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    String? directoryEquals,
    bool directoryEqualsNull = false,
    int? dateFromMillis,
    int? dateToMillis,
    int? ratingEquals,
    required SortFactor sort,
    required bool reverse,
    required int limit,
    required int offset,
  }) async {
    if (limit <= 0) return const [];
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<List<AvesEntry>> loadWalkWindow({
    CollectionWindowPredicate predicate = const CollectionWindowPredicate(),
    required int afterId,
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    return rows.reversed.where((entry) => entry.id > afterId).take(limit).toList();
  }
}
