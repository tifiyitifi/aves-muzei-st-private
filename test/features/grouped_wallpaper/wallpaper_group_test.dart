import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_layout.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Group 0, the derived numbering and the enabled/disabled segment rules.
void main() {
  WallpaperGroup group(String id, {bool enabled = true, bool current = false, String name = ''}) =>
      WallpaperGroup(id: id, name: name, enabled: enabled, current: current, createdAt: 1, updatedAt: 1);

  test('group 0 is a constant with no number, no row and no range', () {
    expect(WallpaperGroup.none.isNone, isTrue);
    expect(WallpaperGroup.none.number, 0);
    expect(WallpaperGroup.none.enabled, isFalse);
    // Its name is an ARB key, so it follows the language like a bundled group.
    expect(WallpaperGroup.none.hasBundledName, isTrue);
  });

  test('a range id is derived from the group id, never from its number', () {
    expect(wallpaperGroupRangeId('wallpaper.group.all'), 'wallpaper.group.all.range');
  });

  test('normalize renumbers, partitions and keeps a single current group', () {
    final normalized = normalizeWallpaperGroups([
      group('a', enabled: false),
      group('b', current: true),
      group('c', enabled: false, current: true),
    ]);

    expect(normalized.map((g) => g.id), ['b', 'a', 'c']);
    expect(normalized.map((g) => g.number), [1, 2, 3]);
    // A disabled group can never be current: the wallpaper falls back to 0.
    expect(normalized.map((g) => g.current), [true, false, false]);
  });

  test('normalize is idempotent', () {
    final once = normalizeWallpaperGroups([group('a', enabled: false), group('b', current: true)]);
    expect(normalizeWallpaperGroups(once), once);
  });

  test('move stays inside its own segment', () {
    final groups = [group('a'), group('b'), group('c', enabled: false), group('d', enabled: false)];

    List<String> idsOf(List<WallpaperGroup> groups) => groups.map((g) => g.id).toList();

    // b is last in the enabled segment and cannot cross into the disabled one.
    expect(idsOf(moveWallpaperGroup(groups, 'b', 1)), ['a', 'b', 'c', 'd']);
    expect(idsOf(moveWallpaperGroup(groups, 'a', 1)), ['b', 'a', 'c', 'd']);
    // The disabled segment moves on its own.
    expect(idsOf(moveWallpaperGroup(groups, 'd', -1)), ['a', 'b', 'd', 'c']);
    expect(idsOf(moveWallpaperGroup(groups, 'c', -1)), ['a', 'b', 'c', 'd']);
    // An unknown id is a no-op, not an exception.
    expect(idsOf(moveWallpaperGroup(groups, 'unknown', 1)), ['a', 'b', 'c', 'd']);
  });

  test('enabling joins the end of the enabled segment, disabling the start of the disabled one', () {
    final groups = [group('a'), group('b'), group('c', enabled: false), group('d', enabled: false)];

    List<String> idsOf(List<WallpaperGroup> groups) => groups.map((g) => g.id).toList();

    expect(idsOf(setWallpaperGroupEnabled(groups, 'c', true)), ['a', 'b', 'c', 'd']);
    expect(idsOf(setWallpaperGroupEnabled(groups, 'a', false)), ['b', 'a', 'c', 'd']);
    // Repeating the current state changes nothing.
    expect(idsOf(setWallpaperGroupEnabled(groups, 'a', true)), ['a', 'b', 'c', 'd']);
    expect(idsOf(setWallpaperGroupEnabled(groups, 'unknown', false)), ['a', 'b', 'c', 'd']);
  });

  test('disabling the current group falls back to group 0', () {
    final groups = [group('a', current: true), group('b')];
    final next = setWallpaperGroupEnabled(groups, 'a', false);

    expect(currentWallpaperGroupId(next), isNull);
    expect(next.every((candidate) => !candidate.current), isTrue);
  });

  test('the enabled segment keeps its order for the notification rotation', () {
    final groups = [group('a'), group('b'), group('c', enabled: false)];
    expect(enabledWallpaperGroups(groups).map((g) => g.id), ['a', 'b']);
    expect(currentWallpaperGroupId(groups), isNull);
  });

  test('renaming drops the bundled-name flag but keeps identity and timestamps', () {
    const bundled = WallpaperGroup(id: 'wallpaper.group.all', name: '@wallpaperGroupDefaultAll', createdAt: 5, updatedAt: 6);
    final renamed = bundled.copyWith(name: 'Mine');

    expect(bundled.hasBundledName, isTrue);
    expect(renamed.hasBundledName, isFalse);
    expect(renamed.name, 'Mine');
    expect(renamed.createdAt, 5);
    expect(renamed.updatedAt, 6);
  });

  test('a description is part of the group identity and survives a rename', () {
    const group = WallpaperGroup(id: 'g', name: 'Trips', description: 'created today', createdAt: 5, updatedAt: 6);
    final renamed = group.copyWith(name: 'Mine', updatedAt: 7);

    expect(renamed.description, 'created today');
    expect(renamed.updatedAt, 7);
    expect(group.copyWith(description: 'summer').description, 'summer');
    // The description participates in equality, so a list change is noticed.
    expect(group, isNot(group.copyWith(description: 'other')));
  });

  test('the switcher style parses by name and defaults to chips', () {
    expect(WallpaperGroupSwitcherStyle.parse(null), WallpaperGroupSwitcherStyle.chips);
    expect(WallpaperGroupSwitcherStyle.parse('unknown'), WallpaperGroupSwitcherStyle.chips);
    expect(WallpaperGroupSwitcherStyle.parse('sections'), WallpaperGroupSwitcherStyle.sections);
    expect(WallpaperGroupSwitcherStyle.parse('grid5'), WallpaperGroupSwitcherStyle.grid5);
  });
}
