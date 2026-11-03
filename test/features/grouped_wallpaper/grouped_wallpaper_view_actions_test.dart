import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view's previous/next controls must be greyed out exactly when the engine
/// would refuse to move, so a tap is never a silent no-op.
void main() {
  const currentEntry = 7;

  GroupedWallpaperState state({
    bool hasPhoto = true,
    GroupedWallpaperStatus status = GroupedWallpaperStatus.ready,
    int count = 3,
    int historyLimit = 200,
    int previous = -1,
  }) => GroupedWallpaperState(
    status: hasPhoto ? status : GroupedWallpaperStatus.unavailable,
    groupId: 'wallpaper.group.dcim',
    groupName: 'DCIM',
    count: count,
    current: hasPhoto ? 0 : -1,
    slots: hasPhoto
        ? const [
            GroupedWallpaperSlot(id: 0, entryId: currentEntry, uri: 'content://media/$currentEntry', title: 'IMG_$currentEntry', photo: 'slots/0/photo.png', width: 1080, height: 2400),
          ]
        : const [],
    previous: previous,
    historyLimit: historyLimit,
  );

  group('previous', () {
    test('needs a photo on screen', () {
      expect(groupedWallpaperCanGoPrevious(state(hasPhoto: false, previous: 0)), isFalse);
    });

    test('is off when the history records nothing', () {
      expect(groupedWallpaperCanGoPrevious(state(historyLimit: 0, previous: 0)), isFalse);
    });

    test('is off until the older frame is baked', () {
      expect(groupedWallpaperCanGoPrevious(state()), isFalse);
    });

    test('is on when the older record is baked and queued', () {
      expect(groupedWallpaperCanGoPrevious(state(previous: 0)), isTrue);
    });

    test('is off once the walk reached the oldest record', () {
      expect(groupedWallpaperCanGoPrevious(state(previous: -1)), isFalse);
    });

    test('is off while the wallpaper is turned off', () {
      expect(groupedWallpaperCanGoPrevious(state(status: GroupedWallpaperStatus.disabled, previous: 0)), isFalse);
    });

    test('is on while the range is locked', () {
      expect(groupedWallpaperCanGoPrevious(state(status: GroupedWallpaperStatus.locked, previous: 0)), isTrue);
    });
  });

  group('next', () {
    test('needs a photo on screen', () {
      expect(groupedWallpaperCanGoNext(state(hasPhoto: false)), isFalse);
    });

    test('is off for a group with a single photo', () {
      expect(groupedWallpaperCanGoNext(state(count: 1)), isFalse);
    });

    test('is on for a group with another photo', () {
      expect(groupedWallpaperCanGoNext(state(count: 2)), isTrue);
    });
  });

  group('group steps', () {
    const rotation = [
      GroupedWallpaperGroup(id: 'wallpaper.group.dcim', number: 1, name: 'DCIM'),
      GroupedWallpaperGroup(id: 'wallpaper.group.camera', number: 2, name: 'Camera'),
    ];

    GroupedWallpaperState groupState({
      List<GroupedWallpaperGroup> groups = rotation,
      String groupId = 'wallpaper.group.dcim',
    }) => GroupedWallpaperState(
      status: GroupedWallpaperStatus.ready,
      groupId: groupId,
      groups: groups,
    );

    test('need a group playing', () {
      expect(groupedWallpaperCanStepGroup(groupState(groupId: 'none'), locked: false), isFalse);
    });

    test('need another enabled group', () {
      expect(
        groupedWallpaperCanStepGroup(groupState(groups: const [GroupedWallpaperGroup(id: 'wallpaper.group.dcim')]), locked: false),
        isFalse,
      );
    });

    test('are on when the rotation has a neighbour and switching is unlocked', () {
      expect(groupedWallpaperCanStepGroup(groupState(), locked: false), isTrue);
    });

    test('are off while the group switch is locked', () {
      expect(groupedWallpaperCanStepGroup(groupState(), locked: true), isFalse);
    });

    test('are off while the grouped wallpaper is turned off', () {
      expect(
        groupedWallpaperCanStepGroup(
          const GroupedWallpaperState(status: GroupedWallpaperStatus.disabled, groupId: 'wallpaper.group.dcim', groups: rotation),
          locked: false,
        ),
        isFalse,
      );
    });
  });
}
