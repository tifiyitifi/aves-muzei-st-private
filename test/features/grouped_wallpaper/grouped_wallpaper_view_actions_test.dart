import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_actions.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The view's previous/next controls must be greyed out exactly when the engine
/// would refuse to move, so a tap is never a silent no-op.
void main() {
  setUpAll(() {
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

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

  group('open wallpaper groups', () {
    test('a view opened from the group page goes back', () {
      expect(
        groupedWallpaperViewGroupNavigation(groupPageBelow: true),
        GroupedWallpaperViewGroupNavigation.back,
      );
    });

    test('a gesture- or notification-opened view pushes the group page', () {
      expect(
        groupedWallpaperViewGroupNavigation(groupPageBelow: false),
        GroupedWallpaperViewGroupNavigation.pushGroupPage,
      );
    });
  });

  group('open in gallery', () {
    AvesEntry photo({String? path = '/storage/emulated/0/DCIM/Camera/IMG_1.jpg'}) => AvesEntry(
      id: 1,
      uri: 'content://media/1',
      path: path,
      contentId: 1,
      pageId: null,
      sourceMimeType: 'image/jpeg',
      width: 300,
      height: 100,
      sourceRotationDegrees: 0,
      sizeBytes: 1,
      sourceTitle: 'IMG_1',
      dateAddedSecs: 1,
      dateModifiedMillis: 2,
      sourceDateTakenMillis: 3,
      durationMillis: 0,
      trashed: false,
      origin: EntryOrigins.mediaStoreContent,
    );

    // A path condition covers a folder tree, while the photo's album is the one
    // shelf it is filed under: the album destination must not be a path filter.
    test("the album target is the photo's stored album and locates it", () {
      final entry = photo();
      final target = groupedWallpaperAlbumTarget(entry, albumDisplayName: 'Camera')!;

      expect(target.filters, hasLength(1));
      final filter = target.filters.single;
      expect(filter, isA<StoredAlbumFilter>());
      expect(filter, isNot(isA<PathFilter>()));
      expect((filter as StoredAlbumFilter).album, '/storage/emulated/0/DCIM/Camera');
      expect(filter.displayName, 'Camera');
      expect(target.locateUri, entry.uri);
    });

    test('the album target needs a directory', () {
      expect(groupedWallpaperAlbumTarget(photo(path: null), albumDisplayName: null), isNull);
      expect(groupedWallpaperAlbumTarget(null, albumDisplayName: null), isNull);
    });

    test('the whole group target is the group media set and locates the photo', () {
      final entry = photo();
      final range = VisibleRange.legacy(
        id: 'g.range',
        scope: VisibleRangeScope.wallpaper,
        ownerId: 'g',
        baseFilters: {PathFilter('/pictures')},
      );
      final target = groupedWallpaperWholeGroupTarget(range, entry: entry);

      expect(target.filters, hasLength(1));
      final filter = target.filters.single;
      expect(filter, isA<SetAndFilter>());
      expect((filter as SetAndFilter).innerFilters, containsAll({MimeFilter.image, PathFilter('/pictures')}));
      expect(target.locateUri, entry.uri);
    });

    test('an unresolved photo locates nothing in the whole group', () {
      final target = groupedWallpaperWholeGroupTarget(null, entry: null);

      expect(target.filters, {MimeFilter.image});
      expect(target.locateUri, isNull);
    });
  });
}
