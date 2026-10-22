import 'package:aves/features/browse_only/services/browse_album_loader.dart';
import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';
import '../../../fake/media_store_service.dart';

/// One album's rows, read from the media store on demand: the album list is
/// whole, but its rows are not held anywhere.
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

  AvesEntry entry(
    int id, {
    String dir = '/album',
    String? path,
    int dateTaken = 0,
    bool trashed = false,
  }) {
    return AvesEntry(
      id: id,
      uri: 'content://$id',
      path: path ?? '$dir/$id.jpg',
      contentId: 100 + id,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: dateTaken,
      durationMillis: 0,
      trashed: trashed,
      origin: EntryOrigins.mediaStoreContent,
    );
  }

  int millis(int year, int month, [int day = 15]) => DateTime.utc(year, month, day).millisecondsSinceEpoch;

  test('loads only its own folder and orders it like the timeline', () async {
    store.honorDirectory = true;
    store.entries = {
      entry(1, dir: '/a', path: '/a/z.jpg', dateTaken: millis(2024, 3)),
      entry(2, dir: '/a', path: '/a/y.jpg', dateTaken: millis(2024, 1)),
      entry(3, dir: '/b', path: '/b/x.jpg', dateTaken: millis(2024, 2)),
    };

    final loader = BrowseAlbumLoader(directory: '/a');
    addTearDown(loader.dispose);
    await loader.load();

    expect(loader.library.loading, isFalse);
    expect(loader.library.error, isNull);
    expect(store.lastPageDirectory, '/a', reason: 'the read must be scoped to the folder');
    final library = loader.library;
    expect(library.length, 2, reason: 'another folder must not leak into the album');

    List<int> ids(List<int> order) => [for (final index in order) library.rowAt(index).id];
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.date, reverse: false)), [1, 2]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.date, reverse: true)), [2, 1]);
    expect(ids(library.mediaIndexes(sort: BrowseMediaSort.name, reverse: false)), [2, 1]);
  });

  test('reads a folder bigger than one page whole', () async {
    store.honorDirectory = true;
    store.entries = {
      for (var i = 1; i <= BrowseLibrary.pageSize * 2 + 1; i++) entry(i, dir: '/a', dateTaken: millis(2024, 1) + i * 60000),
    };

    final loader = BrowseAlbumLoader(directory: '/a');
    addTearDown(loader.dispose);
    await loader.load();

    expect(loader.library.length, BrowseLibrary.pageSize * 2 + 1, reason: 'an album is whole, like its count');
    expect(loader.library.hasMore, isFalse);
  });

  test('a read that fails ends loading and leaves the page with an empty album', () async {
    store.pageError = StateError('media store went away');

    final loader = BrowseAlbumLoader(directory: '/a');
    addTearDown(loader.dispose);
    await loader.load();

    expect(loader.library.loading, isFalse, reason: 'a failed read must not leave the page loading forever');
    expect(loader.library.error, isNotNull);
    expect(loader.library.isEmpty, isTrue);
  });

  test('notifies the page while it loads and once the rows land', () async {
    store.entries = {entry(1, dir: '/a')};
    store.honorDirectory = true;

    final loader = BrowseAlbumLoader(directory: '/a');
    addTearDown(loader.dispose);
    var notifications = 0;
    loader.library.addListener(() => notifications++);

    await loader.load();
    expect(notifications, greaterThanOrEqualTo(2), reason: 'the loading state and the rows both reach the page');
    expect(loader.library.length, 1);
  });
}
