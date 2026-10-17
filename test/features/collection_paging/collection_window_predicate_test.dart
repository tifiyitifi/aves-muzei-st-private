import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/location.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/container/dynamic_album.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/filters/rating.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    // `SetOrFilter` sorts its members by label, which resolves `pContext`.
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  group('predicateForFilters', () {
    test('empty filters match the whole library', () {
      final predicate = predicateForFilters({})!;
      expect(predicate.conjunction, isEmpty);
      expect(predicate.trashedOnly, isFalse);
      expect(predicate.requires, isEmpty);
    });

    test('a single album matches its directory', () {
      final predicate = predicateForFilters({StoredAlbumFilter('/a', null)})!;
      expect(predicate.trashedOnly, isFalse);
      expect(predicate.conjunction.single.sql, 'e.directory = ?');
      expect(predicate.conjunction.single.variables.single.value, '/a');
    });

    test('two albums intersect to nothing', () {
      // Aves intersects a view's filters, so two albums can never both match;
      // the predicate expresses that (unlike the old flat predicate, which
      // punted to the in-memory path).
      final predicate = predicateForFilters({StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)})!;
      expect(predicate.conjunction, hasLength(2));
    });

    test('an album group matches its members with IN', () {
      final group = AlbumGroupFilter(
        Uri.parse('/group'),
        SetOrFilter({StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)}),
      );
      final predicate = predicateForFilters({group})!;
      expect(predicate.conjunction, hasLength(1));
      expect(predicate.conjunction.single.sql, contains('e.directory = ?'));
      expect(predicate.conjunction.single.sql, contains(' OR '));
    });

    test('a tag group reads metadata', () {
      final group = TagGroupFilter(
        Uri.parse('/taggroup'),
        SetOrFilter({TagFilter('sunset'), TagFilter('beach')}),
      );
      final predicate = predicateForFilters({group})!;
      expect(predicate.requires, contains(WindowTable.metadata));
    });

    test('a dynamic album unwraps to its inner filter', () {
      final dynamicAlbum = DynamicAlbumFilter('faves', StoredAlbumFilter('/a', null));
      final predicate = predicateForFilters({dynamicAlbum})!;
      expect(predicate.conjunction.single.sql, 'e.directory = ?');
    });

    test('a location filter reads address', () {
      final predicate = predicateForFilters({LocationFilter(LocationLevel.country, 'France;FR')})!;
      expect(predicate.requires, contains(WindowTable.address));
      expect(predicate.conjunction.single.variables.single.value, 'FR');
    });

    test('a mime filter reads metadata', () {
      final predicate = predicateForFilters({MimeFilter.video})!;
      expect(predicate.requires, contains(WindowTable.metadata));
      expect(predicate.conjunction.single.sql, contains('LOWER(COALESCE(m.mimeType, e.sourceMimeType))'));
    });

    test('a rating filter reads metadata', () {
      final predicate = predicateForFilters({RatingFilter(4)})!;
      expect(predicate.requires, contains(WindowTable.metadata));
    });

    test('a reversed album is negated NULL-safely', () {
      // A bare `NOT (e.directory = ?)` would drop rows whose directory is NULL;
      // Dart's `!test` keeps them, so the negation is "is not true".
      final predicate = predicateForFilters({StoredAlbumFilter('/a', null, reversed: true)})!;
      expect(predicate.conjunction.single.sql, 'COALESCE((e.directory = ?), 0) = 0');
      expect(predicate.conjunction.single.variables.single.value, '/a');
    });

    test('reversed atoms keep working through the same rule', () {
      for (final filter in [
        TagFilter('sunset', reversed: true),
        MimeFilter.video.reverse(),
        RatingFilter(4).reverse(),
        LocationFilter(LocationLevel.country, 'France;FR', reversed: true),
      ]) {
        final predicate = predicateForFilters({filter});
        expect(predicate, isNotNull, reason: '$filter should compile');
        expect(predicate!.conjunction.single.sql, startsWith('COALESCE(('), reason: '$filter should be negated');
      }
    });

    test('a reversed group negates the whole union', () {
      final group = AlbumGroupFilter(
        Uri.parse('/group'),
        SetOrFilter({StoredAlbumFilter('/a', null), StoredAlbumFilter('/b', null)}),
        reversed: true,
      );
      final predicate = predicateForFilters({group})!;
      expect(predicate.conjunction.single.sql, startsWith('COALESCE(('));
      expect(predicate.conjunction.single.sql, contains(' OR '));
    });

    test('trash maps to the trashed-only predicate', () {
      final predicate = predicateForFilters({TrashFilter.instance})!;
      expect(predicate.trashedOnly, isTrue);
      expect(predicate.conjunction, isEmpty);
    });

    test('a live title query compiles, a live regex keeps the legacy path', () {
      // The query bar types a live filter: a title search still compiles, and
      // only the `/regex/` form has no SQL translation.
      expect(predicateForFilters({QueryFilter('a', ACalendar.gregorian, live: true)}), isNotNull);
      expect(predicateForFilters({QueryFilter(r'/a/', ACalendar.gregorian, live: true)}), isNull);
    });

    test('hidden filters become an exclusion fragment', () {
      final predicate = predicateForFilters({}, hidden: {StoredAlbumFilter('/hidden', null)})!;
      // Hiding an album = keeping the entries whose directory is not that album.
      expect(predicate.conjunction.single.sql, 'COALESCE((e.directory = ?), 0) = 0');
      expect(predicate.conjunction.single.variables.single.value, '/hidden');
      // A hidden filter can be any clause, so every optional join is declared.
      expect(predicate.requires, containsAll({WindowTable.dateTaken, WindowTable.metadata, WindowTable.address}));
    });

    test('locked vaults are excluded by directory', () {
      final predicate = predicateForFilters({}, lockedVaultDirs: {'/secret'})!;
      expect(predicate.conjunction.single.sql, contains('NOT IN'));
      expect(predicate.conjunction.single.variables.single.value, '/secret');
    });

    test('a reversed hidden filter is compiled, not ignored', () {
      final predicate = predicateForFilters({}, hidden: {StoredAlbumFilter('/hidden', null, reversed: true)})!;
      expect(predicate.conjunction.single.sql, contains('COALESCE'));
    });

    test('an uncompilable hidden filter keeps the legacy path', () {
      // Never silently ignore a hidden filter: it must not vanish from the view.
      expect(predicateForFilters({}, hidden: {QueryFilter(r'/a/', ACalendar.gregorian)}), isNull);
    });
  });
}
