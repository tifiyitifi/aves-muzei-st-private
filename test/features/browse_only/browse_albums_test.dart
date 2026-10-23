import 'dart:async';

import 'package:aves/features/browse_only/services/browse_albums.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../fake/media_store_service.dart';

/// The album list: one aggregate read of the media store, replaced as a whole,
/// so a count is never seen growing and a folder is whole while the timeline is
/// only a preview.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  late FakeMediaStoreService store;

  setUp(() async {
    await setUpServices();
    store = mediaStoreService as FakeMediaStoreService;
  });

  AvesEntry entry(String dir, String name, {required int dateTaken, int size = 5}) {
    final id = FakeMediaStoreService.nextId;
    return AvesEntry(
      id: id,
      uri: 'content://$dir/$name',
      path: '$dir/$name.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: size,
      sourceTitle: name,
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  test('the list arrives whole, with its counts and covers', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(
        directory: '/zebra',
        count: 12,
        sizeBytes: 60,
        cover: entry('/zebra', 'newest', dateTaken: millis(2024, 3)),
      ),
      MediaStoreAlbumSummary(
        directory: '/apple',
        count: 3,
        sizeBytes: 15,
        cover: entry('/apple', 'only', dateTaken: millis(2024, 1)),
      ),
    ];

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();

    expect(store.albumSummaryRequestCount, 1);
    expect(albums.loading, isFalse);
    expect(albums.error, isNull);
    // The count is the folder's, not the number of rows the browser happens to
    // hold: the timeline's cap can never shrink an album.
    expect(albums.albums.map((v) => (v.name, v.count)), [('zebra', 12), ('apple', 3)]);
    expect(albums.albums.first.cover.sourceTitle, 'newest');
    expect(albums.albums.first.maxDateMillis, millis(2024, 3));
  });

  test('a second load does not re-read the list', () async {
    store.albumSummaries = [];
    final albums = BrowseAlbums();
    addTearDown(albums.dispose);

    await albums.load();
    await albums.load();
    expect(store.albumSummaryRequestCount, 1);
  });

  test('hides albums the user hid from the collection', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/visible', count: 1, sizeBytes: 5, cover: entry('/visible', 'a', dateTaken: millis(2024, 3))),
      MediaStoreAlbumSummary(directory: '/hidden', count: 1, sizeBytes: 5, cover: entry('/hidden', 'b', dateTaken: millis(2024, 2))),
    ];
    final previous = settings.hiddenFilters;
    settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};
    addTearDown(() => settings.hiddenFilters = previous);

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();

    expect(albums.albums.map((v) => v.directory), ['/visible']);
  });

  test('disambiguates same-named folders on other paths', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/dcim/Camera', count: 1, sizeBytes: 5, cover: entry('/dcim/Camera', 'a', dateTaken: millis(2024, 3))),
      MediaStoreAlbumSummary(directory: '/pictures/Camera', count: 1, sizeBytes: 5, cover: entry('/pictures/Camera', 'b', dateTaken: millis(2024, 2))),
    ];

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();

    expect(albums.albums.map((v) => v.name), ['dcim/Camera', 'pictures/Camera']);
  });

  test('orders albums by recency, name or item count', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/zebra', count: 3, sizeBytes: 15, cover: entry('/zebra', 'a', dateTaken: millis(2024, 3))),
      MediaStoreAlbumSummary(directory: '/apple', count: 1, sizeBytes: 5, cover: entry('/apple', 'b', dateTaken: millis(2024, 1))),
      MediaStoreAlbumSummary(directory: '/mango', count: 2, sizeBytes: 10, cover: entry('/mango', 'c', dateTaken: millis(2024, 2))),
    ];

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();

    List<String> names(BrowseAlbumSort sort, {bool reverse = false}) =>
        [for (final album in albums.albumsSorted(sort: sort, reverse: reverse)) album.name];

    // Default: the album holding the newest item first.
    expect(names(BrowseAlbumSort.date), ['zebra', 'mango', 'apple']);
    expect(names(BrowseAlbumSort.date, reverse: true), ['apple', 'mango', 'zebra']);
    expect(names(BrowseAlbumSort.name), ['apple', 'mango', 'zebra']);
    expect(names(BrowseAlbumSort.count), ['zebra', 'mango', 'apple']);
    expect(names(BrowseAlbumSort.count, reverse: true), ['apple', 'mango', 'zebra']);
  });

  test('a failed read can be retried', () async {
    store.albumError = StateError('media store went away');

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();
    expect(albums.error, isNotNull);

    store.albumError = null;
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/dcim/Camera', count: 2, sizeBytes: 10, cover: entry('/dcim/Camera', 'a', dateTaken: millis(2024, 3))),
    ];
    await albums.load();

    expect(albums.error, isNull, reason: 'the error clears when the read is asked for again');
    expect(albums.albums.map((v) => v.directory), ['/dcim/Camera']);
    expect(store.albumSummaryRequestCount, 2);
  });

  test('hiding an album updates the loaded list without re-reading it', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/visible', count: 1, sizeBytes: 5, cover: entry('/visible', 'a', dateTaken: millis(2024, 3))),
      MediaStoreAlbumSummary(directory: '/hidden', count: 1, sizeBytes: 5, cover: entry('/hidden', 'b', dateTaken: millis(2024, 2))),
    ];
    final previous = settings.hiddenFilters;
    settings.hiddenFilters = {};
    addTearDown(() => settings.hiddenFilters = previous);

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();
    expect(albums.albums.map((v) => v.directory), containsAll(['/visible', '/hidden']));

    settings.hiddenFilters = {StoredAlbumFilter('/hidden', null)};

    expect(albums.albums.map((v) => v.directory), ['/visible']);
    expect(albums.albumsSorted(sort: BrowseAlbumSort.name, reverse: false).map((v) => v.directory), ['/visible']);
    expect(store.albumSummaryRequestCount, 1, reason: 'the hidden set is applied to the loaded summaries');
  });

  test('clear drops the list so a handoff can read it again', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/album', count: 1, sizeBytes: 5, cover: entry('/album', 'a', dateTaken: millis(2024, 3))),
    ];
    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();
    expect(albums.albums, hasLength(1));

    albums.clear();
    expect(albums.albums, isEmpty);
    expect(albums.loading, isFalse);

    await albums.load();
    expect(store.albumSummaryRequestCount, 2, reason: 'a cleared list is read again');
    expect(albums.albums, hasLength(1));
  });

  test('a read landing after clear cannot refill the list', () async {
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/album', count: 1, sizeBytes: 5, cover: entry('/album', 'a', dateTaken: millis(2024, 3))),
    ];
    final hold = Completer<void>();
    store.albumHold = hold;
    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });

    final loading = albums.load();
    albums.clear();
    if (!hold.isCompleted) hold.complete();
    await loading;

    expect(albums.albums, isEmpty);
    expect(albums.loading, isFalse);
  });

  test('a read that never answers times out and can be retried', () async {
    final hold = Completer<void>();
    store.albumHold = hold;
    final albums = BrowseAlbums(readTimeout: const Duration(milliseconds: 20));
    addTearDown(albums.dispose);
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });

    await albums.load();
    expect(albums.error, isA<TimeoutException>());
    expect(albums.loading, isFalse);

    store.albumHold = null;
    store.albumSummaries = [
      MediaStoreAlbumSummary(directory: '/album', count: 1, sizeBytes: 5, cover: entry('/album', 'a', dateTaken: millis(2024, 3))),
    ];
    await albums.load();
    expect(albums.error, isNull);
    expect(albums.albums, hasLength(1));
  });

  test('a failed read leaves the list empty and reports the error', () async {
    store.albumError = StateError('media store went away');

    final albums = BrowseAlbums();
    addTearDown(albums.dispose);
    await albums.load();

    expect(albums.loading, isFalse, reason: 'a failed read must not leave the surface loading forever');
    expect(albums.error, isNotNull);
    expect(albums.isEmpty, isTrue);
  });
}
