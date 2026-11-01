import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/wallpaper_auto_advance/data/default_intervals.dart';
import 'package:aves/features/wallpaper_auto_advance/db/wallpaper_interval_options_store.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_interval_catalog.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/sqlite3_loader.dart';

/// Seeding, recovery and the intentional-empty state are what keep Reset and
/// 「Add default intervals」 predictable across restarts.
void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late WallpaperIntervalOptionsStore store;

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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = WallpaperIntervalOptionsStore(db, bundledLoader: () async => bundled);
  });

  tearDown(() => db.close());

  test('a missing key seeds the bundled list once', () async {
    final catalog = await store.loadOrSeed();
    expect(catalog.defaultInterval, WallpaperAdvanceInterval.off);
    expect(catalog.defaults, bundled.intervals);
    expect(catalog.customs, isEmpty);
    expect(catalog.options, bundled.intervals);

    // The seeded value is saved, not recomputed on every read.
    final reloaded = await WallpaperIntervalOptionsStore(db, bundledLoader: () async => const WallpaperIntervalDefaults()).loadOrSeed();
    expect(reloaded.defaults, bundled.intervals);
  });

  test('an intentional empty list survives a restart', () async {
    await store.write(const WallpaperIntervalCatalog(
      defaultInterval: WallpaperAdvanceInterval.off,
      shippedDefaults: [
        WallpaperAdvanceInterval.off,
        WallpaperAdvanceInterval(900),
        WallpaperAdvanceInterval(3600),
        WallpaperAdvanceInterval(86400),
      ],
      defaults: [],
      customs: [],
    ));
    final reloaded = await store.loadOrSeed();
    expect(reloaded.defaults, isEmpty);
    expect(reloaded.customs, isEmpty);
    expect(reloaded.shippedDefaults, bundled.intervals);
    expect(reloaded.missingDefaults, bundled.intervals);
  });

  test('an unreadable value recovers by reseeding', () async {
    await AppMetaStore(db).write({WallpaperIntervalOptionsStore.keyOptions: '{not json'});
    final recovered = await store.loadOrSeed();
    expect(recovered.defaults, bundled.intervals);
    // Malformed entries inside a valid document are skipped, not fatal.
    await AppMetaStore(db).write({WallpaperIntervalOptionsStore.keyOptions: '{"defaults":[900,"bad",900],"customs":[7200,-1]}'});
    final tolerant = await store.loadOrSeed();
    expect(tolerant.defaults, const [WallpaperAdvanceInterval(900)]);
    expect(tolerant.customs, const [WallpaperAdvanceInterval(7200)]);
  });

  test('round-trips built-ins and custom seconds', () async {
    const catalog = WallpaperIntervalCatalog(
      defaultInterval: WallpaperAdvanceInterval(1800),
      shippedDefaults: [
        WallpaperAdvanceInterval.off,
        WallpaperAdvanceInterval(900),
        WallpaperAdvanceInterval(3600),
        WallpaperAdvanceInterval(86400),
      ],
      defaults: [WallpaperAdvanceInterval.off, WallpaperAdvanceInterval(900)],
      customs: [WallpaperAdvanceInterval(7200)],
    );
    await store.write(catalog);
    final reloaded = await store.loadOrSeed();
    expect(reloaded.defaultInterval, bundled.defaultInterval);
    expect(reloaded.defaults, catalog.defaults);
    expect(reloaded.customs, catalog.customs);
    expect(reloaded.options, const [WallpaperAdvanceInterval.off, WallpaperAdvanceInterval(900), WallpaperAdvanceInterval(7200)]);
  });
}
