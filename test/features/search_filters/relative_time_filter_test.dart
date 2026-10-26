import 'package:aves/features/search_filters/model/relative_time_filter.dart';
import 'package:aves/features/search_filters/model/search_assist.dart';
import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:flutter_test/flutter_test.dart';

AvesEntry makeEntry(int id, {int? takenMillis, int? contentId, int sizeBytes = 10}) => AvesEntry(
  id: id,
  uri: 'content://$id',
  path: '/a/$id.jpg',
  contentId: contentId ?? 100 + id,
  pageId: null,
  sourceMimeType: MimeTypes.jpeg,
  width: 100,
  height: 100,
  sourceRotationDegrees: 0,
  sizeBytes: sizeBytes,
  sourceTitle: 'title$id',
  dateAddedSecs: 1,
  dateModifiedMillis: 0,
  sourceDateTakenMillis: takenMillis ?? 0,
  durationMillis: 0,
  trashed: false,
  origin: EntryOrigins.mediaStoreContent,
);

/// A relative window and the filters the assist builds from it.
void main() {
  final now = DateTime(2026, 6, 1, 12);
  RelativeTimeFilter lastDays(int amount) => RelativeTimeFilter(TimeToNow(amount: amount, unit: RelativeTimeUnit.day), now: now);

  test('matches only entries inside the window', () {
    final filter = lastDays(7);
    final inside = makeEntry(1, takenMillis: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch);
    final outside = makeEntry(2, takenMillis: now.subtract(const Duration(days: 8)).millisecondsSinceEpoch);
    final undated = makeEntry(3);

    expect(filter.test(inside), isTrue);
    expect(filter.test(outside), isFalse);
    expect(filter.test(undated), isFalse);
  });

  test('a reversed window keeps the undated entries', () {
    // `!test` in Dart keeps an entry the positive test rejects, and the SQL
    // compiler mirrors that with COALESCE(...) = 0.
    final filter = RelativeTimeFilter(const TimeToNow(amount: 7, unit: RelativeTimeUnit.day), now: now, reversed: true);
    expect(filter.test(makeEntry(1)), isTrue);
    expect(filter.test(makeEntry(2, takenMillis: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch)), isFalse);
  });

  test('the window is anchored at construction', () {
    final early = RelativeTimeFilter(const TimeToNow(amount: 1, unit: RelativeTimeUnit.hour), now: now);
    final late = RelativeTimeFilter(const TimeToNow(amount: 1, unit: RelativeTimeUnit.hour), now: now.add(const Duration(hours: 1)));
    expect(late.cutoffMillis - early.cutoffMillis, const Duration(hours: 1).inMilliseconds);
  });

  test('round-trips through JSON and re-anchors on restore', () {
    final filter = lastDays(30);
    final restored = CollectionFilter.fromJson(filter.toJsonMap());
    expect(restored, isA<RelativeTimeFilter>());
    expect((restored! as RelativeTimeFilter).span, filter.span);
    // Equality is the condition, not the instant it was created.
    expect(restored, filter);
  });

  test('a corrupt span is dropped instead of crashing', () {
    expect(CollectionFilter.fromJson({'type': RelativeTimeFilter.type, 'span': 'soon'}), isNull);
  });

  test('the assist builds the same condition', () {
    final filters = const SearchAssist(recent: AssistRecent(amount: 7, unit: RelativeTimeUnit.day)).toFilters();
    expect(filters.single, isA<RelativeTimeFilter>());
    expect((filters.single as RelativeTimeFilter).span, const TimeToNow(amount: 7, unit: RelativeTimeUnit.day));
  });
}
