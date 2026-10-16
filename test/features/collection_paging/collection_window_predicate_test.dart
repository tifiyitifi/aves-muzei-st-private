import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('predicateForFilters', () {
    test('empty filters match the whole library', () {
      expect(predicateForFilters({}), const CollectionWindowPredicate());
    });

    test('a single album matches its directory', () {
      expect(
        predicateForFilters({StoredAlbumFilter('/a', null)}),
        const CollectionWindowPredicate(directory: '/a'),
      );
    });

    test('two albums need the legacy path', () {
      expect(predicateForFilters({StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)}), isNull);
    });

    test('a reversed album needs the legacy path', () {
      expect(predicateForFilters({StoredAlbumFilter('/a', null, reversed: true)}), isNull);
    });

    test('trash maps to the trashed-only predicate', () {
      expect(
        predicateForFilters({TrashFilter.instance}),
        const CollectionWindowPredicate(excludeTrashed: false, trashedOnly: true),
      );
    });

    test('a live query needs the legacy path', () {
      expect(predicateForFilters({QueryFilter('a', ACalendar.gregorian, live: true)}), isNull);
    });
  });
}
