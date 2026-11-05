import 'package:aves/features/collection_paging/sync/paged_library_ownership.dart';
import 'package:aves/model/source/filter_summary_provider.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

/// One source, one owner: either the in-memory library or the database, never
/// both. The legacy re-read is what would write rows behind the engine.
void main() {
  setUpAll(setUpAllServices);
  tearDownAll(tearDownAllServices);

  group('pagedLibraryOwnsSource', () {
    test('is false until the paging slice attaches its summaries', () {
      expect(pagedLibraryOwnsSource(MediaStoreSource()), isFalse);
    });

    test('is true on a database-backed source', () {
      final source = MediaStoreSource()..summaries = _FakeSummaries();

      expect(pagedLibraryOwnsSource(source), isTrue);
    });
  });

  group('MediaStoreSource.refreshUris', () {
    test('a database-backed source re-reads nothing and asks for no retry', () async {
      final source = MediaStoreSource()..summaries = _FakeSummaries();
      const uris = {'content://media/external/images/media/1'};

      // The empty set is what stops `onStoreChanged` from re-arming itself: the
      // legacy path answers "retry these later", which on a paused source made
      // it reorder the library once per debounce delay.
      expect(await source.refreshUris(uris), isEmpty);
    });

    test('a legacy source keeps its retry contract', () async {
      final source = MediaStoreSource();
      const uris = {'content://media/external/images/media/1'};

      // Nothing is loaded yet, so the legacy path hands the URIs back for a
      // later retry instead of dropping the change.
      expect(await source.refreshUris(uris), uris);
    });
  });
}

class _FakeSummaries extends Fake implements FilterSummaryProvider;
