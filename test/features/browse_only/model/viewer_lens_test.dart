import 'package:aves/features/browse_only/model/viewer_lens.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/events.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';

/// The viewer opened from the browser must keep the rows it was opened with: the
/// browser reads the media store while the catalogue is still being built, so a
/// source event must not add, drop or reorder the entries under the user's swipe.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  AvesEntry entry(int id) => AvesEntry(
    id: id,
    uri: 'content://$id',
    path: '/album/$id.jpg',
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
    sourceDateTakenMillis: 0,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );

  test('the viewer lens keeps its rows and ignores the library', () async {
    final source = MediaStoreSource()..canAnalyze = false;
    addTearDown(source.dispose);
    final entries = [entry(1), entry(2)];
    final lens = browseViewerLens(source, entries);
    addTearDown(lens.dispose);
    var notifications = 0;
    lens.addListener(() => notifications++);

    expect(lens.listenToSource, isFalse);
    expect(lens.fixedSelection, same(entries));
    expect(lens.entryCount, 2);

    // The import adds and removes rows while the viewer is open: the set the
    // browser handed over must not be reshaped behind the user's swipe.
    source.eventBus.fire(EntryAddedEvent({entry(3)}));
    source.eventBus.fire(EntryRemovedEvent({entries.first}));
    await pumpEventQueue();

    expect(lens.entryCount, 2);
    expect(lens.fixedSelection, same(entries));
    expect(notifications, 0);
  });

  test('a lens that follows the source reacts to the same events, which is what the viewer opts out of', () async {
    // The control for the test above: a listening lens holds the viewer's rows
    // too, yet the same event makes it refresh, so the detachment is what keeps
    // the viewer still.
    final source = MediaStoreSource()..canAnalyze = false;
    addTearDown(source.dispose);
    final entries = [entry(1), entry(2)];
    final listening = CollectionLens(source: source, listenToSource: true, fixedSelection: [...entries]);
    addTearDown(listening.dispose);
    var notifications = 0;
    listening.addListener(() => notifications++);

    source.eventBus.fire(EntryAddedEvent({entry(3)}));
    await pumpEventQueue();

    expect(notifications, greaterThan(0));
  });
}
