import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_view_group_target.dart';
import 'package:flutter_test/flutter_test.dart';

/// `groupedWallpaperViewGroupTarget`: the view page's group steps.
///
/// The steps follow the group numbers over the enabled rotation and never enter
/// group 0, so "nothing is playing" stays the system's own state.
void main() {
  const groups = [
    GroupedWallpaperGroup(id: 'a', number: 1, name: 'A'),
    GroupedWallpaperGroup(id: 'b', number: 2, name: 'B'),
    GroupedWallpaperGroup(id: 'c', number: 3, name: 'C'),
  ];

  test('up raises the group number and down lowers it', () {
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'b', delta: 1)?.id, 'c');
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'b', delta: -1)?.id, 'a');
  });

  test('the first and last groups wrap around', () {
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'c', delta: 1)?.id, 'a');
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'a', delta: -1)?.id, 'c');
  });

  test('group 0 is not part of the walk', () {
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'none', delta: 1), isNull);
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'none', delta: -1), isNull);
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: '', delta: 1), isNull);
  });

  test('a group outside the rotation has nowhere to step', () {
    expect(groupedWallpaperViewGroupTarget(groups: groups, currentId: 'disabled-group', delta: 1), isNull);
  });

  test('one enabled group has nothing to switch to', () {
    expect(groupedWallpaperViewGroupTarget(groups: const [GroupedWallpaperGroup(id: 'a')], currentId: 'a', delta: 1), isNull);
    expect(groupedWallpaperViewGroupTarget(groups: const [], currentId: 'a', delta: 1), isNull);
  });
}
