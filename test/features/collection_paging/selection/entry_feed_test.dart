import 'package:aves/features/collection_paging/selection/entry_feed.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:flutter_test/flutter_test.dart';

/// The feed an action runs on: an in-memory set is handed over whole whatever
/// the limit, and only a declared feed refuses past it instead of walking a
/// whole scope into memory.
void main() {
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

  test('a materialized feed hands its set over whole', () async {
    final entries = {entry(1), entry(2)};
    final feed = MaterializedEntryFeed(entries);

    expect(feed.declared, isFalse);
    expect(feed.count, 2);
    expect(feed.contains(entries.first), isTrue);
    expect(await feed.materialize(), entries);
    expect(await feed.first(), entries.first);

    final batches = await feed.batches().toList();
    expect(batches.expand((batch) => batch).toSet(), entries);
  });

  test('a materialized set is handed over whole, whatever the limit', () async {
    final entries = [for (var i = 1; i <= 5; i++) entry(i)];
    final feed = MaterializedEntryFeed(entries);

    // The set is already held, so the limit protects nothing: the legacy
    // selection keeps the actions that used to refuse a large one.
    expect(await feed.materialize(limit: 4), entries.toSet());
    expect(await feed.materialize(), entries.toSet());
  });

  test('batches stay bounded', () async {
    final feed = MaterializedEntryFeed([for (var i = 1; i <= entryFeedBatchSize * 2 + 1; i++) entry(i)]);
    final batches = await feed.batches().toList();

    expect(batches.map((batch) => batch.length), [entryFeedBatchSize, entryFeedBatchSize, 1]);
  });
}
