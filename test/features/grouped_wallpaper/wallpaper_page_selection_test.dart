import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_page_selection.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const groupFilter = WallpaperGroupFilter(groupId: 'g', number: 1, name: 'G');
  final conditionFilter = VisibleRangeCandidateFilter(
    const VisibleRangeCandidate(
      id: 'r',
      kind: VisibleRangeCandidateKind.restriction,
      filters: {},
    ),
  );

  group('item scope', () {
    test('a group card is the group scope', () {
      expect(wallpaperPageItemScope(groupFilter), WallpaperPageSelectionScope.groups);
    });

    test('a condition tile is the condition scope', () {
      expect(wallpaperPageItemScope(conditionFilter), WallpaperPageSelectionScope.conditions);
    });

    test('another filter belongs to neither', () {
      expect(wallpaperPageItemScope(FavouriteFilter.instanceReversed), WallpaperPageSelectionScope.none);
    });
  });

  group('selection scope', () {
    test('an empty selection has no scope', () {
      expect(wallpaperPageSelectionScope(const []), WallpaperPageSelectionScope.none);
    });

    test('groups alone are the group scope', () {
      expect(wallpaperPageSelectionScope([groupFilter]), WallpaperPageSelectionScope.groups);
    });

    test('conditions alone are the condition scope', () {
      expect(wallpaperPageSelectionScope([conditionFilter, conditionFilter]), WallpaperPageSelectionScope.conditions);
    });

    test('a mixed selection is invalid and has no scope', () {
      expect(wallpaperPageSelectionScope([groupFilter, conditionFilter]), WallpaperPageSelectionScope.none);
    });
  });

  group('scope gating', () {
    test('no scope accepts both grids, so either can start a selection', () {
      expect(wallpaperPageItemInScope(WallpaperPageSelectionScope.none, isGroup: true), isTrue);
      expect(wallpaperPageItemInScope(WallpaperPageSelectionScope.none, isGroup: false), isTrue);
    });

    test('a group selection excludes the conditions', () {
      expect(wallpaperPageItemInScope(WallpaperPageSelectionScope.groups, isGroup: true), isTrue);
      expect(wallpaperPageItemInScope(WallpaperPageSelectionScope.groups, isGroup: false), isFalse);
    });

    test('a condition selection excludes the group cards', () {
      expect(wallpaperPageItemInScope(WallpaperPageSelectionScope.conditions, isGroup: false), isTrue);
      expect(wallpaperPageItemInScope(WallpaperPageSelectionScope.conditions, isGroup: true), isFalse);
    });
  });
}
