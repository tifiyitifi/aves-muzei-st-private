import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// The browse index: order, de-duplication, album and month grouping, and the
/// on-demand entry materialization. No database, no collection.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  late BrowseLibrary library;

  setUp(() async {
    await setUpServices();
    library = BrowseLibrary();
  });

  tearDown(() {
    library.dispose();
  });

  AvesEntry entry(
    int id, {
    String dir = '/album',
    String? path,
    int dateTaken = 0,
    bool trashed = false,
    String mime = 'image/jpeg',
    int duration = 0,
  }) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: path ?? '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: mime,
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: duration,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  test('keeps arrival order and ignores re-streamed rows', () {
    library.addEntries([entry(1, dateTaken: millis(2024, 3)), entry(2, dateTaken: millis(2024, 2))]);
    // A resumed import re-walks the rows that are already indexed.
    library.addEntries([entry(1, dateTaken: millis(2024, 3)), entry(3, dateTaken: millis(2024, 1))]);

    expect(library.length, 3);
    expect([for (var i = 0; i < library.length; i++) library.rowAt(i).id], [1, 2, 3]);
  });

  test('leaves trashed rows out', () {
    library.addEntries([entry(1), entry(2, trashed: true)]);
    expect(library.length, 1);
    expect(library.rowAt(0).id, 1);
  });

  test('hides rows of hidden albums from the media grid too', () async {
    library.addEntries([entry(1, dir: '/visible'), entry(2, dir: '/hidden')]);
    final previous = settings.hiddenFilters;
    settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
    addTearDown(() => settings.hiddenFilters = previous);

    final indexes = library.months.expand((month) => month.indexes).toList();
    expect(indexes, [0]);
  });

  test('narrows the index to videos without touching the database', () {
    library.addEntries([
      entry(1, dateTaken: millis(2024, 3), mime: 'video/mp4', duration: 1000),
      entry(2, dateTaken: millis(2024, 3)),
    ]);

    // The media store reports the kind; browsing must not need the catalogue.
    expect(library.videoIndexes, [0]);
    expect(library.rowAt(0).isVideo, isTrue);
    expect(library.rowAt(1).isVideo, isFalse);
  });

  test('groups albums with counts and the newest row as cover', () {
    library.addEntries([
      entry(1, dir: '/zebra', dateTaken: millis(2024, 3)),
      entry(2, dir: '/apple', dateTaken: millis(2024, 3)),
      entry(3, dir: '/zebra', dateTaken: millis(2024, 2)),
    ]);

    final albums = library.albums;
    expect(albums.map((v) => v.name), ['apple', 'zebra']);
    final zebra = albums.last;
    expect(zebra.count, 2);
    // Row 0 is the newest zebra row: the stream is newest first.
    expect(library.rowAt(zebra.coverIndex).id, 1);
    expect(library.rowsOfAlbum('/zebra'), [0, 2]);
  });

  test('hides albums the user hid from the collection', () async {
    library.addEntries([entry(1, dir: '/visible'), entry(2, dir: '/hidden')]);
    final previous = settings.hiddenFilters;
    settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
    addTearDown(() => settings.hiddenFilters = previous);

    expect(library.albums.map((v) => v.directory), ['/visible']);
  });

  test('groups the media grid into months, newest first', () {
    library.addEntries([
      entry(1, dateTaken: millis(2024, 3)),
      entry(2, dateTaken: millis(2024, 3, 1)),
      entry(3, dateTaken: millis(2024, 1)),
    ]);

    final months = library.months;
    expect(months.map((v) => (v.year, v.month)), [(2024, 3), (2024, 1)]);
    expect(months.first.indexes, [0, 1]);
    expect(months.last.indexes, [2]);
  });

  test('orders the timeline by date or by name, both directions', () {
    library.addEntries([
      entry(1, path: '/album/b.jpg', dateTaken: millis(2024, 3)),
      entry(2, path: '/album/a.jpg', dateTaken: millis(2024, 1)),
      entry(3, path: '/album/c.jpg', dateTaken: millis(2024, 2)),
    ]);

    List<int> ids(List<int> order) => [for (final index in order) library.rowAt(index).id];

    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.date, reverse: false)), [1, 3, 2]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.date, reverse: true)), [2, 3, 1]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.name, reverse: false)), [2, 1, 3]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.name, reverse: true)), [3, 1, 2]);
  });

  test('orders albums by recency, name or item count', () {
    library.addEntries([
      entry(1, dir: '/zebra', dateTaken: millis(2024, 3)),
      entry(2, dir: '/apple', dateTaken: millis(2024, 1)),
      entry(3, dir: '/zebra', dateTaken: millis(2024, 2)),
      entry(4, dir: '/mango', dateTaken: millis(2024, 2)),
    ]);

    List<String> names(List<BrowseAlbum> albums) => [for (final album in albums) album.name];

    // Default: the album holding the newest item first.
    expect(names(library.albumsSorted(sort: BrowseAlbumSort.date, reverse: false)), ['zebra', 'mango', 'apple']);
    expect(names(library.albumsSorted(sort: BrowseAlbumSort.date, reverse: true)), ['apple', 'mango', 'zebra']);
    expect(names(library.albumsSorted(sort: BrowseAlbumSort.name, reverse: false)), ['apple', 'mango', 'zebra']);
    expect(names(library.albumsSorted(sort: BrowseAlbumSort.count, reverse: false)), ['zebra', 'apple', 'mango']);
    expect(names(library.albumsSorted(sort: BrowseAlbumSort.count, reverse: true)), ['mango', 'apple', 'zebra']);
  });

  test('orders one album by the same media sort', () {
    library.addEntries([
      entry(1, dir: '/a', path: '/a/z.jpg', dateTaken: millis(2024, 3)),
      entry(2, dir: '/a', path: '/a/y.jpg', dateTaken: millis(2024, 1)),
      entry(3, dir: '/b', path: '/b/x.jpg', dateTaken: millis(2024, 2)),
    ]);

    List<int> ids(List<int> order) => [for (final index in order) library.rowAt(index).id];

    expect(ids(library.albumIndexes('/a', sort: BrowseMediaSort.date, reverse: false)), [1, 2]);
    expect(ids(library.albumIndexes('/a', sort: BrowseMediaSort.name, reverse: false)), [2, 1]);
    expect(library.albumIndexes('/missing', sort: BrowseMediaSort.date, reverse: false), isEmpty);
  });

  test('materializes an entry on demand and reuses it', () {
    library.addEntries([entry(7, dateTaken: millis(2024, 3))]);

    final first = library.entryAt(0);
    expect(first.uri, 'content://7');
    expect(first.sourceDateTakenMillis, millis(2024, 3));
    expect(first.sourceMimeType, 'image/jpeg');
    // The same instance comes back: tiles and the viewer share it.
    expect(identical(first, library.entryAt(0)), isTrue);
  });

  test('synthetic entry ids are unique and disjoint from database ids', () {
    // The index used to mix two id domains (database ids from the import,
    // position-based ids from the scan), so a viewer or selection keyed by id
    // could resolve to another row. Browse owns the id now.
    library.addEntries([entry(0), entry(5), entry(9)]);

    final ids = [for (var index = 0; index < library.length; index++) library.entryAt(index).id];
    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(ids.length), reason: 'two rows must never share an id');
    expect(ids.every((id) => id < 0), isTrue, reason: 'a synthetic id must not alias a real database id');
  });

  test('clears the index for the handoff back to the collection', () {
    library.addEntries([entry(1)]);
    library.clear();
    expect(library.isEmpty, isTrue);
    expect(library.albums, isEmpty);
  });
}
