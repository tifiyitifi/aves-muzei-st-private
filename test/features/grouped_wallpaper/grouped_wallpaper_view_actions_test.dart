import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view's previous/next controls must be greyed out exactly when the engine
/// would refuse to move, so a tap is never a silent no-op.
void main() {
  const currentEntry = 7;

  GroupedWallpaperState state({
    bool hasPhoto = true,
    int count = 3,
    int historyLimit = 200,
    String groupId = 'wallpaper.group.dcim',
    List<GroupedWallpaperRecentEntry> recent = const [],
  }) => GroupedWallpaperState(
    status: hasPhoto ? GroupedWallpaperStatus.ready : GroupedWallpaperStatus.unavailable,
    groupId: groupId,
    groupName: 'DCIM',
    count: count,
    current: hasPhoto ? 0 : -1,
    slots: hasPhoto
        ? const [
            GroupedWallpaperSlot(id: 0, entryId: currentEntry, uri: 'content://media/$currentEntry', title: 'IMG_$currentEntry', photo: 'slots/0/photo.png', width: 1080, height: 2400),
          ]
        : const [],
    recent: recent,
    historyLimit: historyLimit,
  );

  GroupedWallpaperRecentEntry recent(int entryId, {String groupId = 'wallpaper.group.dcim'}) => GroupedWallpaperRecentEntry(entryId: entryId, uri: 'content://media/$entryId', title: 'IMG_$entryId', groupId: groupId);

  group('previous', () {
    test('needs a photo on screen', () {
      expect(groupedWallpaperCanGoPrevious(state(hasPhoto: false, recent: [recent(6)])), isFalse);
    });

    test('is off when the history records nothing', () {
      expect(groupedWallpaperCanGoPrevious(state(historyLimit: 0, recent: [recent(6)])), isFalse);
    });

    test('is off when the history only holds the current photo', () {
      expect(groupedWallpaperCanGoPrevious(state(recent: [recent(currentEntry)])), isFalse);
    });

    test('accepts another entry of the same group', () {
      expect(groupedWallpaperCanGoPrevious(state(recent: [recent(6)])), isTrue);
    });

    test('ignores another group history', () {
      expect(groupedWallpaperCanGoPrevious(state(recent: [recent(6, groupId: 'wallpaper.group.pictures')])), isFalse);
    });

    test('accepts an entry recorded before the group id existed', () {
      expect(groupedWallpaperCanGoPrevious(state(recent: [recent(6, groupId: '')])), isTrue);
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
}
