import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// Seeding from the bundle, the group invariants across restarts, and the
/// per-group range guard.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late WallpaperGroupController controller;

  List<WallpaperGroupDefinition> definitions({bool resolvable = true}) => [
        const WallpaperGroupDefinition(id: 'wallpaper.group.all', nameKey: 'wallpaperGroupDefaultAll', current: true),
        if (resolvable)
          WallpaperGroupDefinition(id: 'wallpaper.group.dcim', nameKey: 'wallpaperGroupDefaultDcim', filters: {PathFilter('/dcim')})
        else
          WallpaperGroupDefinition(id: 'wallpaper.group.dcim', nameKey: 'wallpaperGroupDefaultDcim', filters: {wallpaperDenyAllFilter()}),
        WallpaperGroupDefinition(id: 'wallpaper.group.pictures', nameKey: 'wallpaperGroupDefaultPictures', filters: {PathFilter('/pictures')}),
      ];

  WallpaperGroupController makeController({List<WallpaperGroupDefinition>? bundle}) =>
      WallpaperGroupController(injectedDatabase: db, defaultLoader: () async => bundle ?? definitions());

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    controller = makeController();
    await controller.init();
  });

  tearDown(() => db.close());

  test('seeds the bundled groups once with the bundle order and current group', () async {
    expect(controller.groups.map((group) => group.id), [
      'wallpaper.group.all',
      'wallpaper.group.dcim',
      'wallpaper.group.pictures',
    ]);
    expect(controller.groups.map((group) => group.number), [1, 2, 3]);
    expect(controller.groups.map((group) => group.enabled), everyElement(isTrue));
    expect(controller.current.id, 'wallpaper.group.all');
    // Bundled names are ARB keys, so they follow the app language.
    expect(controller.groups.first.name, '@wallpaperGroupDefaultAll');
    expect(controller.groups.first.hasBundledName, isTrue);

    final range = await controller.groupRange('wallpaper.group.dcim');
    expect(range.scope, VisibleRangeScope.wallpaper);
    expect(range.ownerId, 'wallpaper.group.dcim');
    expect(range.baseFilters, {PathFilter('/dcim')});

    // A second start must not duplicate them.
    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups, hasLength(3));
  });

  test('a group whose folder was not resolvable is seeded closed', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final seeded = WallpaperGroupController(injectedDatabase: fresh, defaultLoader: () async => definitions(resolvable: false));
    await seeded.init();

    final range = await seeded.groupRange('wallpaper.group.dcim');
    expect(range.isRestricted, isTrue);
    expect(range.baseFilters.single, wallpaperDenyAllFilter());
  });

  test('renaming a group survives a restart and a defaults re-apply', () async {
    await controller.renameGroup('wallpaper.group.dcim', 'Trips');
    expect(controller.groups[1].name, 'Trips');
    expect(controller.groups[1].hasBundledName, isFalse);

    // A defaults bump re-applies the bundle but must not overwrite the name.
    await WallpaperGroupStore(db).writeDefaultsVersion(0);
    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups[1].name, 'Trips');
  });

  test('deleting a middle group renumbers and keeps the current group', () async {
    await controller.selectCurrent('wallpaper.group.pictures');
    expect(await controller.deleteGroup('wallpaper.group.dcim'), isTrue);

    expect(controller.groups.map((group) => group.id), ['wallpaper.group.all', 'wallpaper.group.pictures']);
    expect(controller.groups.map((group) => group.number), [1, 2]);
    expect(controller.current.id, 'wallpaper.group.pictures');
    expect(await controller.groupRange('wallpaper.group.dcim'), isA<VisibleRange>());
  });

  test('the last group cannot be deleted', () async {
    await controller.deleteGroup('wallpaper.group.dcim');
    await controller.deleteGroup('wallpaper.group.pictures');
    expect(controller.groups, hasLength(1));
    expect(await controller.deleteGroup('wallpaper.group.all'), isFalse);
    expect(controller.groups, hasLength(1));
  });

  test('disabling the current group falls back to group 0', () async {
    await controller.setEnabled('wallpaper.group.all', false);

    expect(controller.current.isNone, isTrue);
    expect(controller.groups.last.id, 'wallpaper.group.all');
    expect(controller.enabledGroups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.pictures']);
  });

  test('enabling a group moves it to the end of the enabled segment', () async {
    await controller.setEnabled('wallpaper.group.all', false);
    await controller.setEnabled('wallpaper.group.all', true);

    expect(controller.groups.last.id, 'wallpaper.group.all');
    expect(controller.enabledGroups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.pictures', 'wallpaper.group.all']);
    // The current flag was cleared when it was disabled; re-enabling does not
    // silently make it current again.
    expect(controller.current.isNone, isTrue);
  });

  test('moving a group stays inside its segment and persists', () async {
    await controller.moveGroup('wallpaper.group.dcim', -1);
    expect(controller.groups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.all', 'wallpaper.group.pictures']);

    final restarted = makeController();
    await restarted.init();
    expect(restarted.groups.map((group) => group.id), ['wallpaper.group.dcim', 'wallpaper.group.all', 'wallpaper.group.pictures']);
  });

  test('a new group is appended, unrestricted and independent', () async {
    await controller.addGroup(name: 'Trips');
    final added = controller.groups.last;

    expect(added.id, isNot(startsWith('wallpaper.group.')));
    expect(added.name, 'Trips');
    expect(added.number, 4);
    expect(controller.groups.first.id, 'wallpaper.group.all');

    final range = await controller.groupRange(added.id);
    expect(range.baseFilters, isEmpty);

    await controller.saveGroupRange(range.copyWith(baseFilters: {PathFilter('/trips')}));
    expect((await controller.groupRange(added.id)).baseFilters, {PathFilter('/trips')});
    // Other groups are untouched.
    expect((await controller.groupRange('wallpaper.group.pictures')).baseFilters, {PathFilter('/pictures')});
  });

  test('a group range must belong to a known group and the wallpaper scope', () async {
    final range = await controller.groupRange('wallpaper.group.dcim');

    await controller.saveGroupRange(range.copyWith(baseFilters: {PathFilter('/x')}));
    expect((await controller.groupRange('wallpaper.group.dcim')).baseFilters, {PathFilter('/x')});

    await expectLater(
      controller.saveGroupRange(
        const VisibleRange(id: 'gallery', scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId),
      ),
      throwsArgumentError,
    );
    await expectLater(
      controller.saveGroupRange(const VisibleRange(id: 'unknown.range', scope: VisibleRangeScope.wallpaper, ownerId: 'unknown')),
      throwsArgumentError,
    );
    await expectLater(
      controller.saveGroupRange(const VisibleRange(id: 'mismatch', scope: VisibleRangeScope.wallpaper, ownerId: 'wallpaper.group.dcim')),
      throwsArgumentError,
    );
  });

  test('saving a group range bumps the group timestamp and notifies', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    final range = await controller.groupRange('wallpaper.group.all');
    await controller.saveGroupRange(range.copyWith(baseFilters: {MimeFilter.image}));

    expect(notified, 1);
    expect(controller.groups.first.updatedAt, greaterThan(0));
  });
}
