import 'dart:async';

import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
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

  /// One row of either collection, with the URI its table would give it.
  AvesEntry media(int contentId, {required bool video, required int dateMs, String album = '/album'}) {
    final kind = video ? 'video' : 'images';
    return AvesEntry(
      id: contentId,
      uri: 'content://media/external/$kind/media/$contentId',
      path: '$album/$kind-$contentId.${video ? 'mp4' : 'jpg'}',
      contentId: contentId,
      pageId: null,
      sourceMimeType: video ? 'video/mp4' : 'image/jpeg',
      width: 10,
      height: 20,
      sourceRotationDegrees: 0,
      sizeBytes: 5,
      sourceTitle: '$kind-$contentId',
      dateAddedSecs: dateMs ~/ 1000,
      dateModifiedMillis: dateMs,
      sourceDateTakenMillis: dateMs,
      durationMillis: video ? 1000 : null,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );
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

  test('clearing a window during its first read tells its listeners', () async {
    seed(300);
    final hold = Completer<void>();
    store.pageHold = hold;

    final library = BrowseLibrary();
    addTearDown(library.dispose);
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });

    var notifications = 0;
    library.addListener(() => notifications++);

    final loading = library.loadFirstPage();
    expect(library.loading, isTrue);
    final before = notifications;

    // The handoff drops the window while the first page is still in flight: no
    // rows and no error, so the clear itself has to be the event that turns the
    // spinner off.
    library.clear();
    expect(library.loading, isFalse);
    expect(notifications, greaterThan(before), reason: 'the cleared window must tell its listeners');
    expect(library.length, 0);

    hold.complete();
    await loading;
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

  test('two collections with colliding ids page without losing a row', () async {
    const secs = 1700000000;
    // 251 stills and one video in the same second: the video shares the id of
    // the row the first page ends on, which is where one merged cursor used to
    // drop it, because images and videos number their rows in separate tables.
    final all = <AvesEntry>[
      for (var id = 1; id <= 251; id++) media(id, video: false, dateMs: secs * 1000),
      media(2, video: true, dateMs: secs * 1000),
    ];
    store.entries = all.toSet();

    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();
    expect(library.length, BrowseLibrary.pageSize);

    await library.loadMore();
    expect(library.hasMore, isFalse);
    expect(library.length, all.length, reason: 'the video shares a content id with a still and must still be read');
    expect([for (var i = 0; i < library.length; i++) library.rowAt(i).uri], contains('content://media/external/video/media/2'));
  });

  test('a page the platform filtered out is read past instead of stalling the window', () async {
    seed(400);
    // The platform looked at the first page and kept none of its rows, but its
    // cursor still moved: the rows behind it are what the window has to read.
    store.emptyPages = 1;

    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();
    expect(store.pageRequestCount, 2);
    expect(library.length, 150, reason: 'the rows behind the filtered page arrive');
    expect(library.error, isNull);
  });

  test('a page whose cursor cannot advance stops with an error', () async {
    seed(400);
    store.emptyPages = 2;
    store.emptyPageCursorStalls = true;

    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();
    expect(library.length, 0);
    expect(store.pageRequestCount, 2);
    expect(library.error, isNotNull, reason: 'asking the same page forever is not progress');
    expect(library.hasMore, isFalse);
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

  test('an empty library loads as empty, not as an error', () async {
    seed(0);
    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();

    expect(library.length, 0);
    expect(library.loading, isFalse);
    expect(library.error, isNull);
    expect(library.hasMore, isFalse);
    expect(store.pageRequestCount, 1);
  });

  test('a page that never answers times out and can be retried', () async {
    seed(300);
    final hold = Completer<void>();
    store.pageHold = hold;
    final library = BrowseLibrary(pageTimeout: const Duration(milliseconds: 20));
    addTearDown(library.dispose);
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });

    await library.loadFirstPage();
    expect(library.error, isA<TimeoutException>());
    expect(library.loading, isFalse);
    expect(library.length, 0);

    store.pageHold = null;
    await library.retry();
    expect(library.error, isNull);
    expect(library.length, BrowseLibrary.pageSize);
  });

  test('an exact multiple of the page size ends with one empty read, not a lost row', () async {
    seed(BrowseLibrary.pageSize * 2);
    final library = BrowseLibrary();
    addTearDown(library.dispose);

    await library.loadFirstPage();
    await library.loadMore();
    expect(library.length, BrowseLibrary.pageSize * 2);
    expect(library.hasMore, isTrue, reason: 'a full last page is not proof of the end');

    await library.loadMore();
    expect(library.length, BrowseLibrary.pageSize * 2);
    expect(library.hasMore, isFalse);
    expect(store.pageRequestCount, 3);
  });

  test('the default timeline limit is 5000 and only the user passes it', () async {
    seed(BrowseLibrary.previewRowLimit + 200);
    final library = BrowseLibrary(rowLimit: BrowseLibrary.previewRowLimit);
    addTearDown(library.dispose);

    await library.loadFirstPage();
    while (!library.atLimit) {
      await library.loadMore();
    }
    expect(library.length, BrowseLibrary.previewRowLimit);
    expect(library.hasMore, isFalse);

    final requests = store.pageRequestCount;
    await library.loadMore();
    expect(store.pageRequestCount, requests, reason: 'the preview does not grow on its own');

    await library.loadMore(beyondPreviewLimit: true);
    expect(store.pageRequestCount, requests + 1);
    expect(library.length, BrowseLibrary.previewRowLimit + 200);
    expect(library.hasMore, isFalse);
  });

  test('a disposed window does not read', () async {
    seed(10);
    final library = BrowseLibrary()..dispose();
    await library.loadFirstPage();
    expect(store.pageRequestCount, 0, reason: 'a disposed window has nothing to fill');
  });
}
