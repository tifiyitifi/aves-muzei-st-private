import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperState`: the `state.json` contract, and its tolerance of a
/// file written by another build or truncated by a crash.
void main() {
  const state = GroupedWallpaperState(
    generation: 3,
    status: GroupedWallpaperStatus.ready,
    groupId: 'wallpaper.group.dcim',
    groupNumber: 2,
    groupName: 'DCIM',
    count: 42,
    entryId: 7,
    entryTitle: 'IMG_7',
    photo: GroupedWallpaperState.photoFileName,
    width: 1080,
    height: 2400,
    bakedAt: 1234,
  );

  test('round-trips every field', () {
    expect(GroupedWallpaperState.tryFromJsonMap(state.toJsonMap()), state);
  });

  test('a state from another version is ignored', () {
    final json = state.toJsonMap()..['version'] = GroupedWallpaperState.currentVersion + 1;
    expect(GroupedWallpaperState.tryFromJsonMap(json), isNull);
  });

  test('an unknown status is ignored instead of guessed', () {
    final json = state.toJsonMap()..['status'] = 'paused';
    expect(GroupedWallpaperState.tryFromJsonMap(json), isNull);
  });

  test('ready without a photo degrades to the placeholder', () {
    final json = state.toJsonMap()..['photo'] = '';
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.unavailable);
    expect(parsed.hasPhoto, isFalse);
    expect(parsed.entryId, isNull);
  });

  test('locked keeps the frame it froze on', () {
    final json = state.toJsonMap()..['status'] = GroupedWallpaperStatus.locked.name;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.locked);
    expect(parsed.entryId, 7);
    expect(parsed.photo, GroupedWallpaperState.photoFileName);
    expect(parsed.hasPhoto, isTrue);
  });

  test('disabled keeps the frame the feature stopped on', () {
    final json = state.toJsonMap()..['status'] = GroupedWallpaperStatus.disabled.name;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.disabled);
    expect(parsed.status.keepsFrame, isTrue);
    expect(parsed.entryId, 7);
    expect(parsed.hasPhoto, isTrue);
  });

  test('disabled without a frame stays disabled instead of failing', () {
    final json = state.toJsonMap()
      ..['status'] = GroupedWallpaperStatus.disabled.name
      ..['photo'] = '';
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    // Nothing was ever baked, so there is nothing to freeze: the renderer shows
    // the placeholder, but the feature is still off.
    expect(parsed.status, GroupedWallpaperStatus.disabled);
    expect(parsed.hasPhoto, isFalse);
    expect(parsed.entryId, isNull);
  });

  test('a state with no photo drops the entry of the previous frame', () {
    final json = state.toJsonMap()
      ..['status'] = GroupedWallpaperStatus.emptyGroup.name
      ..['photo'] = ''
      ..['entryId'] = 7;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.emptyGroup);
    expect(parsed.hasPhoto, isFalse);
    expect(parsed.entryId, isNull);
    expect(parsed.photo, isEmpty);
  });

  test('missing fields fall back to defaults instead of throwing', () {
    final parsed = GroupedWallpaperState.tryFromJsonMap({
      'version': GroupedWallpaperState.currentVersion,
      'status': GroupedWallpaperStatus.unavailable.name,
    })!;
    expect(parsed.generation, 0);
    expect(parsed.groupId, isEmpty);
    expect(parsed.count, 0);
    expect(parsed.bakedAt, 0);
    expect(parsed.hasPhoto, isFalse);
  });

  test('a wrong-typed field is ignored, not fatal', () {
    final json = state.toJsonMap()
      ..['count'] = 'many'
      ..['groupId'] = 7;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.count, 0);
    expect(parsed.groupId, isEmpty);
  });
}
