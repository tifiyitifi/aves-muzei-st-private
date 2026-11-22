import 'package:aves/features/collection_paging/services/media_set_append.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';

void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  final a = StoredAlbumFilter('/a', null);
  final b = StoredAlbumFilter('/b', null);
  final c = StoredAlbumFilter('/c', null);

  group('mergeMediaSetFilters', () {
    test('appending to an empty set opens the selection alone', () {
      expect(mergeMediaSetFilters(null, {a}), {a});
    });

    test('several selected albums are folded into one deduplicated union', () {
      final merged = mergeMediaSetFilters(null, {a, b, c});

      expect(merged, hasLength(1));
      expect(merged.single, isA<SetOrFilter>());
      expect((merged.single as SetOrFilter).innerFilters, {a, b, c});
    });

    test('an album already in the media set is not added twice', () {
      final base = {SetOrFilter({a, b})};

      expect(mergeMediaSetFilters(base, {b, c}), {SetOrFilter({a, b, c})});
    });

    test('the other conditions of the media set are kept alongside the union', () {
      final base = {a, FavouriteFilter.instance};

      expect(mergeMediaSetFilters(base, {b}), {SetOrFilter({a, b}), FavouriteFilter.instance});
    });

    test('repeated appends of overlapping albums compose without duplicates', () {
      final first = mergeMediaSetFilters(null, {a, b});
      final second = mergeMediaSetFilters(first, {b, c});
      final third = mergeMediaSetFilters(second, {a, c});

      expect(third, {SetOrFilter({a, b, c})});
    });

    test('a reversed album scope is kept intact instead of being flattened', () {
      final reversed = StoredAlbumFilter('/a', null, reversed: true);

      expect(mergeMediaSetFilters(null, {reversed, b}), {reversed, b});
    });

    test('an empty union is kept as a condition instead of disappearing', () {
      final empty = SetOrFilter(const <CollectionFilter>{});

      expect(mergeMediaSetFilters({empty}, {a}), {empty, a});
    });
  });
}
