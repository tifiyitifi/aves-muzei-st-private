import 'package:aves/features/collection_paging/query/collection_filter_sql.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The wallpaper media set: images only, narrowed by the group's range, and
/// empty when the range fails closed.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  VisibleRange range({Set<CollectionFilter> baseFilters = const {}, List<VisibleRangeRule> rules = const []}) => VisibleRange(
        id: 'g.range',
        scope: VisibleRangeScope.wallpaper,
        ownerId: 'g',
        baseFilters: baseFilters,
        rules: rules,
      );

  test('a group without a range uses every image', () {
    expect(wallpaperMediaSetFilter(null), MimeFilter.image);
  });

  test('an unrestricted range still uses every image', () {
    expect(wallpaperMediaSetFilter(range()), MimeFilter.image);
  });

  test('a range narrows the images to its result', () {
    final filter = wallpaperMediaSetFilter(range(baseFilters: {PathFilter('/pictures')}));

    expect(filter, isA<SetAndFilter>());
    final members = (filter as SetAndFilter).innerFilters;
    expect(members, containsAll({MimeFilter.image, PathFilter('/pictures')}));
  });

  test('a fail-closed range keeps no image at all', () {
    final closed = range(baseFilters: {wallpaperDenyAllFilter()});
    final filter = wallpaperMediaSetFilter(closed)!;

    expect(closed.isRestricted, isTrue);
    expect(filter, isA<SetAndFilter>());
    expect((filter as SetAndFilter).innerFilters, containsAll({MimeFilter.image, wallpaperDenyAllFilter()}));
    // The deny-all base is a container with no member: nothing matches it in
    // memory, and the paged path compiles it to a false predicate.
    expect(wallpaperDenyAllFilter(), isA<SetOrFilter>());
    expect(filterTestFragment(wallpaperDenyAllFilter())?.sql, '0 = 1');
  });

  test('an active restriction is applied to the media set', () {
    final filter = wallpaperMediaSetFilter(
      range(
        baseFilters: {PathFilter('/pictures')},
        rules: [
          VisibleRangeRule(id: 'r1', rangeId: 'g.range', kind: VisibleRangeRuleKind.restriction, filters: {MimeFilter.image, PathFilter('/pictures/holiday')}),
        ],
      ),
    );

    expect(filter, isA<SetAndFilter>());
    expect((filter as SetAndFilter).innerFilters, contains(MimeFilter.image));
  });
}
