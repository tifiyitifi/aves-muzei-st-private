import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:flutter_test/flutter_test.dart';

AvesEntry makeEntry(int id, String mimeType) => AvesEntry(
      id: id,
      uri: 'content://$id',
      path: '/a/$id',
      contentId: id,
      pageId: null,
      sourceMimeType: mimeType,
      width: 100,
      height: 100,
      sourceRotationDegrees: 0,
      sizeBytes: 10,
      sourceTitle: 'title$id',
      dateAddedSecs: 1,
      dateModifiedMillis: 0,
      sourceDateTakenMillis: 0,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );

/// The grid adapter: a candidate is a filter set, not a single filter.
void main() {
  final image = MimeFilter.image;
  final video = MimeFilter.video;

  test('a candidate filter tests the conjunction of its filters', () {
    final filter = VisibleRangeCandidateFilter(
      VisibleRangeCandidate.customBase(name: 'images', filters: {image}),
    );
    expect(filter.test(makeEntry(1, MimeTypes.jpeg)), isTrue);
    expect(filter.test(makeEntry(2, MimeTypes.mp4)), isFalse);
  });

  test('an unrestricted candidate matches everything', () {
    final filter = VisibleRangeCandidateFilter(VisibleRangeCandidate.unrestricted);
    expect(filter.test(makeEntry(1, MimeTypes.mp4)), isTrue);
    expect(filter.test(makeEntry(2, MimeTypes.jpeg)), isTrue);
  });

  test('summary and grid copies have different keys', () {
    final candidate = VisibleRangeCandidate.customBase(name: 'images', filters: {image});
    final grid = VisibleRangeCandidateFilter(candidate);
    final summary = VisibleRangeCandidateFilter(candidate, summary: true);
    expect(grid.key, isNot(summary.key));
    expect(grid.props, isNot(summary.props));
  });

  test('the universal label falls back to the filter labels', () {
    final filter = VisibleRangeCandidateFilter(
      VisibleRangeCandidate.customBase(name: '', filters: {image, video}),
    );
    expect(filter.universalLabel, isNotEmpty);
    expect(filter.category, VisibleRangeCandidateFilter.type);
    expect(filter.exclusiveProp, isFalse);
  });

  test('a reversed filter keeps its reverse semantics', () {
    final reversed = MimeFilter.video.reverse();
    final filter = VisibleRangeCandidateFilter(
      VisibleRangeCandidate.customBase(name: 'not video', filters: {reversed}),
    );
    expect(filter.test(makeEntry(1, MimeTypes.jpeg)), isTrue);
    expect(filter.test(makeEntry(2, MimeTypes.mp4)), isFalse);
  });
}
