import 'dart:async';

import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';
import '../../../fake/media_store_service.dart';

/// The browse window's reads: a bounded first page, a keyset cursor for the
/// pages after it, and a preview limit only the user can pass.
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

  /// [count] rows, newest first, one minute apart: enough to see page boundaries.
  void seed(int count, {String album = '/album'}) {
    final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
    store.entries = {
      for (var i = 1; i <= count; i++)
        FakeMediaStoreService.newImage(album, 'seed$i', id: i, contentId: i)..sourceDateTakenMillis = base + i * 60000,
    };
  }

  test('the first page is one bounded read and the next one follows its cursor', () async {
    seed(600);
    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();
    expect(library.length, BrowseLibrary.pageSize, reason: 'the first screen must not wait on the library');
    expect(store.lastPageLimit, BrowseLibrary.pageSize);
    expect(store.lastPageBeforeId, isNull, reason: 'the first page starts at the newest row');
    expect(library.hasMore, isTrue);

    final boundary = library.rowAt(library.length - 1);
    await library.loadMore();
    expect(library.length, BrowseLibrary.pageSize * 2);
    // The page resumes after the last row of the previous one, so the read is
    // bounded by the page rather than by the rows behind it.
    expect(store.lastPageBeforeSortDateSecs, boundary.bestDateMillis ~/ 1000);
    expect(store.lastPageBeforeId, boundary.contentId);

    await library.loadMore();
    expect(library.length, 600);
    expect(library.hasMore, isFalse, reason: 'the library is exhausted');
    expect(store.pageRequestCount, 3);
  });

  test('the timeline stops at its preview limit and only the user passes it', () async {
    expect(BrowseLibrary.previewRowLimit, 5000, reason: 'the preview is a few MB of compact rows');
    seed(700);
    final library = BrowseLibrary(rowLimit: 500);
    addTearDown(library.dispose);

    await library.loadFirstPage();
    await library.loadMore();
    expect(library.length, 500);
    expect(library.atLimit, isTrue);
    expect(library.hasMore, isFalse, reason: 'the preview does not grow on its own');

    final requests = store.pageRequestCount;
    await library.loadMore();
    expect(store.pageRequestCount, requests, reason: 'a capped window ignores the scroll trigger');

    await library.loadMore(beyondPreviewLimit: true);
    expect(library.length, 700, reason: 'the user asking for more is not the preview growing');
    expect(library.hasMore, isFalse);
  });

  test('a page in flight cannot refill a window cleared for the handoff', () async {
    seed(300);
    final hold = Completer<void>();
    store.pageHold = hold;

    final library = BrowseLibrary();
    addTearDown(library.dispose);

    final loading = library.loadFirstPage();
    library.clear();
    hold.complete();
    await loading;

    expect(library.length, 0, reason: 'a page landing after the handoff must not index into a cleared window');
  });

  test('a failed page keeps the rows and can be retried', () async {
    seed(300);
    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();
    expect(library.length, BrowseLibrary.pageSize);

    store.pageError = StateError('media store went away');
    await library.loadMore();
    expect(library.length, BrowseLibrary.pageSize, reason: 'a broken read is not the end of the library');
    expect(library.error, isNotNull);
    expect(library.hasMore, isFalse, reason: 'the window must not keep asking on its own');

    store.pageError = null;
    await library.retry();
    expect(library.error, isNull);
    expect(library.length, 300);
  });

  test('an album window reads its folder whole, with no preview limit', () async {
    seed(600, album: '/album');
    store.honorDirectory = true;
    store.entries = {
      ...store.entries,
      FakeMediaStoreService.newImage('/other', 'other', id: 9999, contentId: 9999),
    };

    final library = BrowseLibrary(directory: '/album');
    addTearDown(library.dispose);

    await library.loadAll();
    expect(library.length, 600, reason: 'an album is whole, like its count');
    expect(library.hasMore, isFalse);
    expect(store.lastPageDirectory, '/album', reason: 'the read must be scoped to the folder');
  });

  test('a disposed window does not read', () async {
    seed(10);
    final library = BrowseLibrary()..dispose();
    await library.loadFirstPage();
    expect(store.pageRequestCount, 0, reason: 'a disposed window has nothing to fill');
  });
}
