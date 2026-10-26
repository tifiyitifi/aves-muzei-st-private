import 'package:aves/features/search_filters/model/range_assist_filter.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:flutter_test/flutter_test.dart';

AvesEntry makeEntry(
  int id, {
  int? takenMillis,
  int? contentId,
  int? sizeBytes,
  int width = 100,
  int height = 200,
  int rotation = 0,
}) =>
    AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '/a/$id.jpg',
      contentId: contentId,
      pageId: null,
      sourceMimeType: MimeTypes.jpeg,
      width: width,
      height: height,
      sourceRotationDegrees: rotation,
      sizeBytes: sizeBytes,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 0,
      sourceDateTakenMillis: takenMillis ?? 0,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );

/// A bounded numeric condition: both bounds are inclusive, an open side is
/// unbounded, and a missing value never matches.
void main() {
  test('a date range is inclusive', () {
    final filter = RangeAssistFilter(AssistRangeField.takenDate, min: 100, max: 200);
    expect(filter.test(makeEntry(1, takenMillis: 100)), isTrue);
    expect(filter.test(makeEntry(2, takenMillis: 200)), isTrue);
    expect(filter.test(makeEntry(3, takenMillis: 99)), isFalse);
    expect(filter.test(makeEntry(4, takenMillis: 201)), isFalse);
  });

  test('a missing date never matches, even a max-only range', () {
    final filter = RangeAssistFilter(AssistRangeField.takenDate, max: 200);
    expect(filter.test(makeEntry(1)), isFalse);
    // The reversed filter keeps it: the positive test is simply false.
    expect(filter.reverse().test(makeEntry(1)), isTrue);
  });

  test('a size range reads the file size', () {
    final filter = RangeAssistFilter(AssistRangeField.size, min: 1 << 20);
    expect(filter.test(makeEntry(1, sizeBytes: 2 << 20)), isTrue);
    expect(filter.test(makeEntry(2, sizeBytes: 1 << 20)), isTrue);
    expect(filter.test(makeEntry(3, sizeBytes: 1 << 19)), isFalse);
  });

  test('width and height read the displayed size', () {
    final width = RangeAssistFilter(AssistRangeField.width, min: 150);
    final height = RangeAssistFilter(AssistRangeField.height, max: 50);
    final entry = makeEntry(1, width: 100, height: 50);
    expect(width.test(entry), isFalse);
    expect(height.test(entry), isTrue);
  });

  test('the displayed size swaps for a rotated entry', () {
    final entry = makeEntry(1, width: 100, height: 200, rotation: 90);
    expect(RangeAssistFilter(AssistRangeField.width, min: 200, max: 200).test(entry), isTrue);
    expect(RangeAssistFilter(AssistRangeField.height, min: 100, max: 100).test(entry), isTrue);
  });

  test('a content id range ignores entries without one', () {
    final filter = RangeAssistFilter(AssistRangeField.contentId, min: 10, max: 20);
    expect(filter.test(makeEntry(1, contentId: 15)), isTrue);
    expect(filter.test(makeEntry(2, contentId: 21)), isFalse);
    expect(filter.test(makeEntry(3)), isFalse);
  });

  test('round-trips through JSON', () {
    final filters = [
      RangeAssistFilter(AssistRangeField.takenDate, min: 10, max: 20),
      RangeAssistFilter(AssistRangeField.size, min: 30),
      RangeAssistFilter(AssistRangeField.height, max: 40),
      RangeAssistFilter(AssistRangeField.contentId, min: 50, max: 60, reversed: true),
    ];
    for (final filter in filters) {
      expect(CollectionFilter.fromJson(filter.toJsonMap()), filter);
    }
  });

  test('an unknown field is dropped instead of crashing', () {
    expect(CollectionFilter.fromJson({'type': RangeAssistFilter.type, 'field': 'nope'}), isNull);
  });
}
