import 'dart:async';

import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';
import '../../../fake/media_store_service.dart';

/// The browse index: whole from the media store, dropped when the collection
/// takes over.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  setUp(() async {
    await setUpServices();
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('the browse scan did not reach the expected state');
  }

  test('a scan stopped by the handoff never refills the index it was cleared for', () async {
    final store = mediaStoreService as FakeMediaStoreService;
    final controller = StreamController<AvesEntry>();
    addTearDown(controller.close);
    store.entriesStream = controller.stream;

    final library = BrowseLibrary();
    addTearDown(library.dispose);

    final scan = library.scan();
    for (var i = 1; i <= 250; i++) {
      controller.add(FakeMediaStoreService.newImage('/album', 'scan$i'));
    }
    await until(() => library.length == 250);
    expect(library.length, 250);

    // What the handoff does: the browse surface is disposed, the index dropped.
    library.clear();
    expect(library.length, 0);

    for (var i = 251; i <= 500; i++) {
      controller.add(FakeMediaStoreService.newImage('/album', 'scan$i'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(library.length, 0, reason: 'a stopped scan must not index into a cleared library');
    // The scan itself is released, so nothing is left waiting on the stream.
    await expectLater(scan, completes);
  });

  test('a disposed index does not resubscribe to the media store', () async {
    final store = mediaStoreService as FakeMediaStoreService;
    store.entries = {};

    final library = BrowseLibrary()..dispose();
    await library.scan();

    expect(store.entryRequestCount, 0, reason: 'a disposed index has nothing to fill');
  });

  test('the last batch notifies even when it arrived within the notify interval', () async {
    final store = mediaStoreService as FakeMediaStoreService;
    final controller = StreamController<AvesEntry>();
    addTearDown(controller.close);
    store.entriesStream = controller.stream;

    final library = BrowseLibrary();
    addTearDown(library.dispose);

    final scan = library.scan();
    var notifications = 0;
    library.addListener(() => notifications++);
    // Two batches back to back: the first may be coalesced, the ending must not.
    for (var i = 1; i <= 500; i++) {
      controller.add(FakeMediaStoreService.newImage('/album', 'batch$i'));
    }
    await controller.close();
    await expectLater(scan, completes);

    expect(library.length, 500);
    expect(notifications, greaterThan(0), reason: 'the last batch must reach the surfaces');
  });
}
