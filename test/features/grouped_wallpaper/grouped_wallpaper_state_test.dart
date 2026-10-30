import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_gestures.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_history_limit.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

/// `GroupedWallpaperState`: the `state.json` contract, the slot queue, the
/// ordering metadata, and its tolerance of a file written by another build or
/// truncated by a crash.
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

  const state = GroupedWallpaperState(
    generation: 3,
    status: GroupedWallpaperStatus.ready,
    groupId: 'wallpaper.group.dcim',
    groupNumber: 2,
    groupName: 'DCIM',
    count: 42,
    current: 0,
    next: 1,
    next2: 2,
    slots: [
      GroupedWallpaperSlot(
        id: 0,
        entryId: 7,
        uri: 'content://media/7',
        title: 'IMG_7',
        photo: 'slots/0/photo.png',
        effectHome: 'slots/0/home.png',
        effectLock: 'slots/0/lock.png',
        width: 1080,
        height: 2400,
      ),
      GroupedWallpaperSlot(id: 1, entryId: 8, uri: 'content://media/8', title: 'IMG_8', photo: 'slots/1/photo.png', width: 1080, height: 2400),
      GroupedWallpaperSlot(id: 2, entryId: 9, uri: 'content://media/9', title: 'IMG_9', photo: 'slots/2/photo.png', width: 1080, height: 2400),
    ],
    recent: [
      GroupedWallpaperRecentEntry(entryId: 7, uri: 'content://media/7', title: 'IMG_7', groupId: 'wallpaper.group.dcim'),
      GroupedWallpaperRecentEntry(entryId: 6, uri: 'content://media/6', title: 'IMG_6', groupId: 'wallpaper.group.dcim'),
    ],
    cursor: 5,
    newestEntryId: 9,
    ordering: GroupedWallpaperOrdering.inOrder,
    paused: true,
    historyLimit: 500,
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
    expect(parsed.currentSlot?.effectHome, 'slots/0/home.png');
    expect(parsed.currentSlot?.effectLock, 'slots/0/lock.png');
    expect(parsed.recent.map((entry) => entry.entryId), [7, 6]);
    expect(parsed.recent.first.groupId, 'wallpaper.group.dcim');
    expect(parsed.cursor, 5);
    expect(parsed.newestEntryId, 9);
    expect(parsed.ordering, GroupedWallpaperOrdering.inOrder);
    expect(parsed.paused, isTrue);
    expect(parsed.historyLimit, 500);
  });

  test('the group-switch lock travels with the state', () {
    final locked = state.copyWith(switchLocked: true);
    expect(GroupedWallpaperState.tryFromJsonMap(locked.toJsonMap())!.switchLocked, isTrue);
    // A file written before the lock existed reads as unlocked.
    final json = state.toJsonMap()..remove('switchLocked');
    expect(GroupedWallpaperState.tryFromJsonMap(json)!.switchLocked, isFalse);
  });

  test('a file written before the history limit existed records at the default', () {
    final json = state.toJsonMap()..remove('historyLimit');
    expect(GroupedWallpaperState.tryFromJsonMap(json)!.historyLimit, GroupedWallpaperHistoryLimit.defaultLimit);

    final outOfRange = state.toJsonMap()..['historyLimit'] = 100000;
    expect(GroupedWallpaperState.tryFromJsonMap(outOfRange)!.historyLimit, GroupedWallpaperHistoryLimit.maxLimit);
  });

  test('a v3 file reads as playing, with no group on its history', () {
    final json = state.toJsonMap()
      ..['version'] = 3
      ..remove('paused')
      ..['recent'] = [
        {'entryId': 7, 'uri': 'content://media/7', 'title': 'IMG_7'},
      ];
    final parsed = GroupedWallpaperState.tryFromJsonMap(json)!;
    expect(parsed.paused, isFalse);
    expect(parsed.recent.single.groupId, isEmpty);
  });

  test('a state from another version is ignored', () {
    final json = state.toJsonMap()..['version'] = GroupedWallpaperState.currentVersion + 1;
    expect(GroupedWallpaperState.tryFromJsonMap(json), isNull);
  });

  test('an unknown status is ignored instead of guessed', () {
    final json = state.toJsonMap()..['status'] = 'paused';
    expect(GroupedWallpaperState.tryFromJsonMap(json), isNull);
  });

  test('an unknown ordering falls back to the default', () {
    final json = state.toJsonMap()..['ordering'] = 'shuffled';
    expect(GroupedWallpaperState.tryFromJsonMap(json)!.ordering, GroupedWallpaperOrdering.defaultOrdering);
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
    expect(parsed.recent, isEmpty);
  });

  test('a v2 state keeps its queue and starts the ordering metadata empty', () {
    final parsed = GroupedWallpaperState.tryFromJsonMap({
      'version': 2,
      'generation': 4,
      'status': 'ready',
      'groupId': 'group.1',
      'groupNumber': 1,
      'groupName': 'DCIM',
      'count': 12,
      'current': 0,
      'next': 1,
      'next2': -1,
      'slots': [
        {'id': 0, 'entryId': 7, 'uri': '', 'title': 'IMG_7', 'photo': 'slots/0/photo.png'},
        {'id': 1, 'entryId': 8, 'uri': '', 'title': 'IMG_8', 'photo': 'slots/1/photo.png'},
      ],
      'gestures': {'doubleTap': 'nextArtwork', 'threeFinger': 'viewArtwork'},
      'bakedAt': 9,
    })!;
    expect(parsed.version, GroupedWallpaperState.currentVersion);
    expect(parsed.queueLength, 2);
    expect(parsed.recent, isEmpty);
    expect(parsed.cursor, 0);
    expect(parsed.newestEntryId, 0);
    expect(parsed.ordering, GroupedWallpaperOrdering.defaultOrdering);
    expect(parsed.gestures, const GroupedWallpaperGestures());
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
    expect(parsed.recent, isEmpty);
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

  test('the recent list is de-duplicated and capped', () {
    final recent = [
      for (var i = 0; i < GroupedWallpaperState.maxRecent + 1; i++) GroupedWallpaperRecentEntry(entryId: i + 1),
    ];
    final promoted = GroupedWallpaperState.promoteRecent(recent, slot(0, 10));

    expect(promoted.first.entryId, 10);
    expect(promoted.length, GroupedWallpaperState.maxRecent);
    // The promoted photo is moved, not duplicated, and the oldest one is dropped.
    expect(promoted.where((entry) => entry.entryId == 10).length, 1);
    expect(promoted.map((entry) => entry.entryId), isNot(contains(GroupedWallpaperState.maxRecent + 1)));
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
