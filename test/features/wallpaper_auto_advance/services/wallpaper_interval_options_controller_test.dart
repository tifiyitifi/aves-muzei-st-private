import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/db/wallpaper_interval_options_store.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';
import 'package:aves/features/wallpaper_auto_advance/services/wallpaper_interval_options_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/sqlite3_loader.dart';

/// Adding, deleting, Reset and 「Add default intervals」 are the whole contract of
/// the shared option list.
void main() {
  setUpAll(ensureSqlite3Loaded);

  const bundled = WallpaperIntervalDefaults(
    version: 1,
    defaultInterval: WallpaperAdvanceInterval.off,
    intervals: [
      WallpaperAdvanceInterval.off,
      WallpaperAdvanceInterval(900),
      WallpaperAdvanceInterval(3600),
      WallpaperAdvanceInterval(86400),
    ],
  );

  late AppDatabase db;
  late WallpaperIntervalOptionsStore store;
  late List<({Set<WallpaperAdvanceInterval> removed, bool all, WallpaperAdvanceInterval fallback})> resets;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = WallpaperIntervalOptionsStore(db, bundledLoader: () async => bundled);
    resets = [];
  });

  tearDown(() => db.close());

  WallpaperIntervalOptionsController makeController() => WallpaperIntervalOptionsController(
        injectedDatabase: db,
        bundledLoader: () async => bundled,
        selectionReset: ({required removed, required all, required fallback}) async {
          resets.add((removed: removed, all: all, fallback: fallback));
        },
      );

  Future<void> writeCatalog({List<WallpaperAdvanceInterval> defaults = const [], List<WallpaperAdvanceInterval> customs = const []}) => store.write(
        WallpaperIntervalCatalog(
          defaultInterval: bundled.defaultInterval,
          shippedDefaults: bundled.intervals,
          defaults: defaults,
          customs: customs,
        ),
      );

  test('loads and seeds the bundled list', () async {
    final controller = makeController();
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.ensureLoaded();
    expect(controller.isLoaded, isTrue);
    expect(controller.catalog!.defaults, bundled.intervals);
    expect(controller.catalog!.customs, isEmpty);
    expect(notifications, 1);
    controller.dispose();
  });

  test('adding an existing option writes nothing', () async {
    await writeCatalog(defaults: bundled.intervals, customs: [const WallpaperAdvanceInterval(7200)]);
    final controller = makeController();
    await controller.ensureLoaded();
    final before = controller.catalog;

    expect(await controller.addCustom(const WallpaperAdvanceInterval(900)), const WallpaperAdvanceInterval(900));
    expect(controller.catalog, before);
    expect(await controller.addCustom(const WallpaperAdvanceInterval(7200)), const WallpaperAdvanceInterval(7200));
    expect(controller.catalog, before);
    controller.dispose();
  });

  test('a missing built-in is restored as built-in, not as a custom option', () async {
    await writeCatalog(defaults: const [WallpaperAdvanceInterval.off], customs: const []);
    final controller = makeController();
    await controller.ensureLoaded();

    await controller.addCustom(const WallpaperAdvanceInterval(3600));

    final catalog = controller.catalog!;
    expect(catalog.defaults, contains(const WallpaperAdvanceInterval(3600)));
    expect(catalog.isCustom(const WallpaperAdvanceInterval(3600)), isFalse);
    controller.dispose();
  });

  test('a new value becomes a custom option', () async {
    await writeCatalog(defaults: bundled.intervals, customs: const []);
    final controller = makeController();
    await controller.ensureLoaded();

    await controller.addCustom(const WallpaperAdvanceInterval(7200));

    final catalog = controller.catalog!;
    expect(catalog.customs, [const WallpaperAdvanceInterval(7200)]);
    expect(catalog.isCustom(const WallpaperAdvanceInterval(7200)), isTrue);
    controller.dispose();
  });

  test('deleting customs removes only those and resets only their users', () async {
    await writeCatalog(
      defaults: bundled.intervals,
      customs: const [WallpaperAdvanceInterval(7200), WallpaperAdvanceInterval(10800)],
    );
    final controller = makeController();
    await controller.ensureLoaded();

    await controller.deleteCustoms({const WallpaperAdvanceInterval(7200)});

    expect(controller.catalog!.customs, [const WallpaperAdvanceInterval(10800)]);
    expect(resets, hasLength(1));
    expect(resets.single.removed, {const WallpaperAdvanceInterval(7200)});
    expect(resets.single.all, isFalse);
    expect(resets.single.fallback, WallpaperAdvanceInterval.off);
    controller.dispose();
  });

  test('deleting nothing is a no-op', () async {
    final controller = makeController();
    await controller.ensureLoaded();
    await controller.deleteCustoms(const {});
    expect(resets, isEmpty);
    controller.dispose();
  });

  test('Reset clears built-ins and customs and resets every selection', () async {
    await writeCatalog(defaults: bundled.intervals, customs: const [WallpaperAdvanceInterval(7200)]);
    final controller = makeController();
    await controller.ensureLoaded();

    await controller.resetAll();

    expect(controller.catalog!.defaults, isEmpty);
    expect(controller.catalog!.customs, isEmpty);
    expect(controller.catalog!.options, isEmpty);
    expect(resets, hasLength(1));
    expect(resets.single.removed, isEmpty);
    expect(resets.single.all, isTrue);
    expect(resets.single.fallback, WallpaperAdvanceInterval.off);

    // The empty state is persisted, not re-seeded.
    final reloaded = makeController();
    await reloaded.ensureLoaded();
    expect(reloaded.catalog!.options, isEmpty);
    reloaded.dispose();
    controller.dispose();
  });

  test('Add default intervals only fills the missing built-ins', () async {
    await writeCatalog(defaults: const [WallpaperAdvanceInterval.off], customs: const [WallpaperAdvanceInterval(7200)]);
    final controller = makeController();
    await controller.ensureLoaded();

    await controller.addMissingDefaults();

    final catalog = controller.catalog!;
    expect(catalog.defaults, bundled.intervals);
    expect(catalog.customs, [const WallpaperAdvanceInterval(7200)]);
    expect(resets, isEmpty);

    // Idempotent: nothing left to add, nothing written again.
    final before = controller.catalog;
    await controller.addMissingDefaults();
    expect(controller.catalog, before);
    controller.dispose();
  });

  test('notifies the pages on every catalog change', () async {
    await writeCatalog(defaults: bundled.intervals, customs: const []);
    final controller = makeController();
    await controller.ensureLoaded();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.addCustom(const WallpaperAdvanceInterval(7200));
    expect(notifications, 1);
    await controller.deleteCustoms({const WallpaperAdvanceInterval(7200)});
    expect(notifications, 2);
    await controller.addMissingDefaults();
    // Everything is already present, so there is nothing to notify about.
    expect(notifications, 2);
    controller.dispose();
  });
}
