import 'package:aves/features/search_filters/model/range_assist_filter.dart';
import 'package:aves/features/search_filters/model/relative_time_filter.dart';
import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The assist value: what each condition turns into, and how a condition is
/// replaced or dropped without touching its neighbours.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  test('an empty assist builds nothing', () {
    expect(SearchAssist.empty.isEmpty, isTrue);
    expect(SearchAssist.empty.hasOther, isFalse);
    expect(SearchAssist.empty.toFilters(), isEmpty);
  });

  test('a path condition is the single directory filter', () {
    final include = const SearchAssist(path: PathAssist(path: '/DCIM/Camera')).toFilters();
    expect(include.single, PathFilter('/DCIM/Camera'));

    final exclude = const SearchAssist(path: PathAssist(path: '/DCIM/Camera', mode: PathAssistMode.exclude)).toFilters();
    expect(exclude.single, PathFilter('/DCIM/Camera', reversed: true));
    expect(exclude.single.reversed, isTrue);
  });

  test('a path alone is not an "other" condition', () {
    const assist = SearchAssist(path: PathAssist(path: '/DCIM'));
    expect(assist.hasOther, isFalse);
    expect(assist.isEmpty, isFalse);
  });

  test('date, size and id become one ranged filter each', () {
    const assist = SearchAssist(
      takenDate: AssistIntRange(min: 10, max: 20),
      size: AssistIntRange(min: 100),
      contentId: AssistIntRange(max: 5),
    );
    final filters = assist.toFilters().whereType<RangeAssistFilter>().toList();
    expect(filters, hasLength(3));
    expect(filters.map((f) => f.field), {AssistRangeField.takenDate, AssistRangeField.size, AssistRangeField.contentId});
  });

  test('a dimension range expands to width and height', () {
    const assist = SearchAssist(
      dimension: AssistDimension(
        width: AssistIntRange(min: 1000),
        height: AssistIntRange(max: 500),
      ),
    );
    final filters = assist.toFilters().whereType<RangeAssistFilter>().toList();
    expect(filters.map((f) => f.field), {AssistRangeField.width, AssistRangeField.height});
    expect(filters.firstWhere((f) => f.field == AssistRangeField.width).min, 1000);
    expect(filters.firstWhere((f) => f.field == AssistRangeField.height).max, 500);
  });

  test('an empty dimension adds nothing', () {
    expect(const SearchAssist(dimension: AssistDimension()).toFilters(), isEmpty);
  });

  test('a recent window becomes a relative filter', () {
    final filters = const SearchAssist(recent: AssistRecent(amount: 7, unit: RelativeTimeUnit.day)).toFilters();
    expect((filters.single as RelativeTimeFilter).span, const TimeToNow(amount: 7, unit: RelativeTimeUnit.day));
  });

  test('one extension is a query, several are OR-ed', () {
    final single = SearchAssist.empty.withExtensions({'JPG'}).toFilters(calendar: ACalendar.gregorian);
    expect(single.single, QueryFilter('EXT=jpg', ACalendar.gregorian));

    final several = SearchAssist.empty.withExtensions({'JPG', '.png'}).toFilters(calendar: ACalendar.gregorian);
    final union = several.single as SetOrFilter;
    expect(
      union.innerFilters,
      {QueryFilter('EXT=jpg', ACalendar.gregorian), QueryFilter('EXT=png', ACalendar.gregorian)},
    );
  });

  test('extensions are stored without a dot and lowercased', () {
    expect(SearchAssist.empty.withExtensions({'JPG', '.Png'}).extensions, {'jpg', 'png'});
  });

  test('removing one condition keeps the others', () {
    const assist = SearchAssist(
      path: PathAssist(path: '/DCIM'),
      size: AssistIntRange(min: 1),
      recent: AssistRecent(amount: 1, unit: RelativeTimeUnit.hour),
    );
    final withoutSize = assist.without(AssistField.size);
    expect(withoutSize.size, isNull);
    expect(withoutSize.path, assist.path);
    expect(withoutSize.recent, assist.recent);
    expect(withoutSize.toFilters(), hasLength(2));
  });

  test('clearing the other conditions keeps the path', () {
    const assist = SearchAssist(
      path: PathAssist(path: '/DCIM'),
      takenDate: AssistIntRange(min: 1),
      extensions: {'jpg'},
    );
    final cleared = assist.clearOther();
    expect(cleared.path, assist.path);
    expect(cleared.hasOther, isFalse);
    expect(cleared.toFilters(), hasLength(1));
  });

  test('every condition together is a conjunction of filters', () {
    const assist = SearchAssist(
      path: PathAssist(path: '/DCIM'),
      takenDate: AssistIntRange(min: 1, max: 2),
      size: AssistIntRange(min: 3),
      dimension: AssistDimension(width: AssistIntRange(min: 4)),
      contentId: AssistIntRange(max: 5),
      recent: AssistRecent(amount: 3, unit: RelativeTimeUnit.hour),
      extensions: {'jpg'},
    );
    // path, date, size, width, id, recent, extension
    expect(assist.toFilters(), hasLength(7));
  });
}
