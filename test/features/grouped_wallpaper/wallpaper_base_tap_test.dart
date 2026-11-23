import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_sections.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:flutter_test/flutter_test.dart';

/// The base section is a union, so a tap names one source; only 「All images」
/// speaks for the whole surface.
void main() {
  VisibleRangeRule source() => VisibleRangeRule(id: 'source.1', rangeId: 'r', kind: VisibleRangeRuleKind.source, filters: {MimeFilter.image});

  test('a source tile toggles only its own mark', () {
    final candidate = VisibleRangeCandidate.fromRule(source()).copyWithSurfaceMarks(surfaces: 0, active: false);
    expect(wallpaperBaseTap(candidate), WallpaperBaseTap.toggleRule);
  });

  test('All images clears the surface instead of picking a source', () {
    expect(wallpaperBaseTap(VisibleRangeCandidate.unrestricted), WallpaperBaseTap.clearSurface);
  });

  test('a placeholder or a surface summary asks for nothing', () {
    const placeholder = VisibleRangeCandidate(
      id: 'section.none',
      kind: VisibleRangeCandidateKind.base,
      filters: {},
      placeholder: true,
    );
    expect(wallpaperBaseTap(placeholder), WallpaperBaseTap.none);
    expect(wallpaperBaseTap(VisibleRangeCandidate.fromRule(source()).copyWithReadOnly(true)), WallpaperBaseTap.none);
  });
}
