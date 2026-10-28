import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperState`: the `state.json` contract, the slot queue, and its
/// tolerance of a file written by another build or truncated by a crash.
void main() {
  GroupedWallpaperSlot slot(int id, int entryId) => GroupedWallpaperSlot(
        id: id,
        entryId: entryId,
        uri: 'content://media/$entryId',
        title: 'IMG_$entryId',
        photo: 'slots/$id/photo.png',
        width: 1080,
        height: 2400,
      );

  final state = GroupedWallpaperState(
    generation: 3,
    status: GroupedWallpaperStatus.ready,
    groupId: 'wallpaper.group.dcim',
    groupNumber: 2,
    groupName: 'DCIM',
    count: 42,
    current: 0,
    next: 1,
    next2: 2,
    slots: [slot(0, 7), slot(1, 8), slot(2, 9)],
    bakedAt: 1234,
  );

  test('round-trips every field', () {
    final parsed = GroupedWallpaperState.tryFromJsonMap(state.toJsonMap())!;
    expect(parsed, state);
    expect(parsed.currentSlot?.entryId, 7);
    expect(parsed.nextSlot?.entryId, 8);
    expect(parsed.next2Slot?.entryId, 9);
    expect(parsed.entryId, 7);
    expect(parsed.entryTitle, 'IMG_7');
  });

  test('a state from another version is ignored', () {
    final json = state.toJsonMap()..['version'] = GroupedWallpaperState.currentVersion + 1;
    expect(GroupedWallpaperState.tryFromJsonMap(json), isNull);
  });

  test('an unknown status is ignored instead of guessed', () {
    final json = state.toJsonMap()..['status'] = 'paused';
    expect(GroupedWallpaperState.tryFromJsonMap(json), isNull);
  });

  test('ready without a slot degrades to the placeholder', () {
    final json = state.toJsonMap()
      ..['slots'] = <Object?>[]
      ..['current'] = -1;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.unavailable);
    expect(parsed.hasPhoto, isFalse);
  });

  test('locked keeps the queue it froze on', () {
    final json = state.toJsonMap()..['status'] = GroupedWallpaperStatus.locked.name;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.locked);
    expect(parsed.hasPhoto, isTrue);
    expect(parsed.queueLength, 3);
  });

  test('disabled keeps the frame the feature stopped on', () {
    final json = state.toJsonMap()..['status'] = GroupedWallpaperStatus.disabled.name;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.status, GroupedWallpaperStatus.disabled);
    expect(parsed.status.keepsFrame, isTrue);
    expect(parsed.hasPhoto, isTrue);
  });

  test('a slot without a photo is dropped', () {
    final json = state.toJsonMap()
      ..['slots'] = [
        {'id': 0, 'entryId': 7, 'photo': ''},
      ]
      ..['current'] = 0;
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.slots, isEmpty);
    expect(parsed.status, GroupedWallpaperStatus.unavailable);
  });

  test('a v1 state is read as a single-slot queue', () {
    final parsed = GroupedWallpaperState.tryFromJsonMap({
      'version': 1,
      'generation': 4,
      'status': 'ready',
      'groupId': 'group.1',
      'groupNumber': 1,
      'groupName': 'DCIM',
      'count': 12,
      'entryId': 5,
      'entryTitle': 'IMG_5',
      'photo': 'current.png',
      'width': 2340,
      'height': 2340,
      'bakedAt': 9,
    })!;
    expect(parsed.version, GroupedWallpaperState.currentVersion);
    expect(parsed.generation, 4);
    expect(parsed.current, 0);
    expect(parsed.next, -1);
    expect(parsed.currentSlot?.photo, 'current.png');
    expect(parsed.currentSlot?.entryId, 5);
    expect(parsed.currentSlot?.title, 'IMG_5');
    expect(parsed.hasPhoto, isTrue);
  });

  test('missing fields fall back to defaults instead of throwing', () {
    final parsed = GroupedWallpaperState.tryFromJsonMap({
      'version': GroupedWallpaperState.currentVersion,
      'status': GroupedWallpaperStatus.unavailable.name,
    })!;
    expect(parsed.generation, 0);
    expect(parsed.groupId, isEmpty);
    expect(parsed.count, 0);
    expect(parsed.current, -1);
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

  test('the runtime only matches the state it was written for', () {
    const runtime = GroupedWallpaperRuntime(generation: 3, current: 1, next: 2);
    expect(runtime.matches(state), isTrue);
    expect(runtime.matches(state.copyWith(generation: 4)), isFalse);
  });

  test('the runtime round-trips through JSON', () {
    const runtime = GroupedWallpaperRuntime(generation: 3, current: 1, next: 2, refillRequested: true);
    expect(GroupedWallpaperRuntime.tryFromJsonMap(runtime.toJsonMap()), runtime);
    expect(GroupedWallpaperRuntime.tryFromJsonMap({'current': 1}), isNull);
  });
}
