import 'package:aves/features/collection_paging/sync/paged_discoverer.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row whose media-store item is gone leaves nothing for the generation-gated
/// sync to find: the change query asks the store for the rows modified after the
/// cursor, and a deleted row is not there to answer. The sweep is what settles
/// them, so its rules are worth pinning: remove what the store disowned, by row
/// id rather than by content id, never touching a volume that is not mounted,
/// and refuse an answer that would empty the library.
void main() {
  late _FakeMediaStore mediaStore;
  late _FakeDb database;
  late PagedDiscoverer discoverer;

  setUp(() {
    mediaStore = _FakeMediaStore();
    database = _FakeDb();
    discoverer = PagedDiscoverer(
      mediaStore: mediaStore,
      mediaFetch: _FakeMediaFetch(),
      database: database,
      catalogEntry: (_) async {},
    );
  });

  test('a row the store no longer serves is removed by its row id', () async {
    database.contentIds = {1, 2, 3};
    mediaStore.obsolete = {2};

    final removed = await discoverer.reconcileObsoleteMediaStoreRows(mountedVolumePaths: {'/storage/emulated/0'});

    expect(removed, 1);
    // The store answers content id 2; the row is id 1002. Deleting the content
    // id would remove nothing and leave the dead row behind.
    expect(database.removed, {1002});
    expect(mediaStore.asked, {1, 2, 3});
    expect(database.askedUnder, {'/storage/emulated/0'});
  });

  test('a live library removes nothing', () async {
    database.contentIds = {1, 2, 3};

    final removed = await discoverer.reconcileObsoleteMediaStoreRows(mountedVolumePaths: {'/storage/emulated/0'});

    expect(removed, 0);
    expect(database.removed, isEmpty);
  });

  test('a sweep that would drop most of the library is refused', () async {
    database.contentIds = {1, 2, 3};
    // An unreadable or half-scanned store answers that nothing exists.
    mediaStore.obsolete = {1, 2};

    final removed = await discoverer.reconcileObsoleteMediaStoreRows(mountedVolumePaths: {'/storage/emulated/0'});

    expect(removed, 0);
    expect(database.removed, isEmpty);
  });

  test('an unmounted volume is never asked about', () async {
    final removed = await discoverer.reconcileObsoleteMediaStoreRows(mountedVolumePaths: {});

    expect(removed, 0);
    expect(database.askedUnder, isNull);
    expect(mediaStore.asked, isNull);
  });
}

class _FakeMediaStore extends Fake implements MediaStoreService {
  Set<int> obsolete = {};
  Set<int>? asked;

  @override
  Future<List<int>> checkObsoleteContentIds(List<int?> knownContentIds) async {
    asked = knownContentIds.whereType<int>().toSet();
    return knownContentIds.whereType<int>().where(obsolete.contains).toList();
  }
}

class _FakeMediaFetch extends Fake implements MediaFetchService;

class _FakeDb extends Fake implements LocalMediaDb {
  Set<int> contentIds = {};
  final Set<int> removed = {};
  Set<String>? askedUnder;

  @override
  Future<Set<int>> loadMediaStoreContentIdsUnder(Set<String> directories) async {
    askedUnder = directories;
    return contentIds;
  }

  @override
  Future<Set<AvesEntry>> loadEntriesByContentIds(Set<int> ids) async => {
        for (final contentId in ids) _entry(contentId),
      };

  @override
  Future<void> removeIds(Set<int> ids, {Set<EntryDataType>? dataTypes}) async => removed.addAll(ids);

  @override
  Future<void> insertEntries(Set<AvesEntry> entries) async {}

  /// Row id 1000 + content id, so a content-id delete is distinguishable from a
  /// row-id delete in the assertions.
  static AvesEntry _entry(int contentId) => AvesEntry(
        id: 1000 + contentId,
        uri: 'content://media/external/images/media/$contentId',
        path: '/storage/emulated/0/a/$contentId.jpg',
        contentId: contentId,
        pageId: null,
        sourceMimeType: 'image/jpeg',
        width: 10,
        height: 20,
        sourceRotationDegrees: 0,
        sizeBytes: 5,
        sourceTitle: '$contentId',
        dateAddedSecs: 1,
        dateModifiedMillis: 2,
        sourceDateTakenMillis: 3,
        durationMillis: 0,
        trashed: false,
        origin: 0,
      );
}
