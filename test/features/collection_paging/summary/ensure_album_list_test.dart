import 'package:aves/features/collection_paging/summary/ensure_album_list.dart';
import 'package:aves/features/collection_paging/summary/paged_summary_registry.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/source/filter_summary_provider.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../common.dart';

/// The album list must answer from whichever engine owns the source, even when
/// no collection lens ran in this process (a top-level album destination, or a
/// wallpaper pick that starts on the album list).
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  late MediaStoreSource source;

  setUp(() async {
    await setUpServices();
    source = MediaStoreSource();
    source.canAnalyze = false;
  });

  tearDown(() async {
    // The provider registry is keyed by source (app-wide); do not leak this test's.
    forgetPagedSummaries(source);
  });

  AvesEntry entry(int id) => AvesEntry(
    id: id,
    uri: 'content://media/external/images/media/${100 + id}',
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

  test('an attached provider only loads its album domain', () async {
    final provider = _RecordingSummaries();
    source.summaries = provider;

    await ensureAlbumListData(source);

    expect(provider.ensureAlbumsCalls, 1);
    expect(source.summaries, same(provider));
  });

  test('a fully loaded source is left on its in-memory directories', () async {
    await source.loadDates();
    source.addEntries({entry(1)});
    expect(source.allEntries, isNotEmpty);

    await ensureAlbumListData(source);

    expect(source.summaries, isNull, reason: 'a legacy list must not switch to the database behind it');
  });

  test('an entry-free source without a provider attaches the database one', () async {
    expect(source.allEntries, isEmpty);
    expect(source.summaries, isNull);

    await ensureAlbumListData(source);

    expect(source.summaries, isNotNull, reason: 'nothing else can answer the album list of an entry-free source');
  });
}

/// A provider that records the domain preload and fails loudly on anything else.
class _RecordingSummaries implements FilterSummaryProvider {
  int ensureAlbumsCalls = 0;

  @override
  Future<void> ensureAlbums() async {
    ensureAlbumsCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
