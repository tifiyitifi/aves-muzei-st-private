import 'package:aves/features/drift_db/addresses/address_table.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_table.dart';
import 'package:aves/features/drift_db/catalog/catalog_tables.dart';
import 'package:aves/features/drift_db/covers/cover_table.dart';
import 'package:aves/features/drift_db/debug/debug_table.dart';
import 'package:aves/features/drift_db/dynamic_albums/dynamic_album_table.dart';
import 'package:aves/features/drift_db/entries/entry_table.dart';
import 'package:aves/features/drift_db/favourites/favourite_table.dart';
import 'package:aves/features/drift_db/migration/migration_v2.dart';
import 'package:aves/features/drift_db/migration/migration_v3.dart';
import 'package:aves/features/drift_db/migration/migration_v4.dart';
import 'package:aves/features/drift_db/migration/migration_v5.dart';
import 'package:aves/features/drift_db/migration/migration_v6.dart';
import 'package:aves/features/drift_db/migration/migration_v7.dart';
import 'package:aves/features/drift_db/trash/trash_table.dart';
import 'package:aves/features/drift_db/vaults/vault_table.dart';
import 'package:aves/features/drift_db/video_playback/video_playback_table.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_table.dart';
import 'package:aves/features/meta_settings/db/settings_values_table.dart';
import 'package:aves/features/visible_range/db/visible_range_tables.dart';
import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Fork-owned Drift database for local media metadata.
///
/// Opened on `<getDatabasesPath()>/aves.drift.db`, a fresh file seeded once from
/// the legacy `metadata.db` (see `migration/legacy_import.dart`). The schema
/// starts at version 1; future changes add a `MigrationVN` and bump
/// [schemaVersion] following the same per-version layout used by the reference
/// project (`lib/models/db/migration`).
///
/// This is the only place that aggregates the domain tables: Drift requires a
/// single `@DriftDatabase` for code generation. Each table still lives in its
/// own domain directory.
@DriftDatabase(
  tables: [
    EntriesTable,
    DateTakenTable,
    MetadataTable,
    AddressesTable,
    FavouritesTable,
    CoversTable,
    DynamicAlbumsTable,
    VaultsTable,
    TrashTable,
    VideoPlaybackTable,
    DebugTable,
    AppMetaTable,
    SettingsValuesTable,
    VisibleRangePresetRows,
    VisibleRangeRows,
    VisibleRangeRuleRows,
    VisibleRangeSessionRows,
    VisibleRangeKeyValues,
    WallpaperGroupRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  // Classic constructor form (not the Dart 3.13 `new(...)` sugar): drift_dev's
  // bundled analyzer cannot parse `new` yet, and it must parse this file to
  // generate `app_database.g.dart`.
  // ignore: unnecessary_type_name_in_constructor
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          // Forward-only, per-version migration chain (iris-style).
          if (from < 2) await MigrationV2(this).run(m);
          if (from < 3) await MigrationV3(this).run(m);
          if (from < 4) await MigrationV4(this).run(m);
          if (from < 5) await MigrationV5(this).run(m);
          if (from < 6) await MigrationV6(this).run(m);
          if (from < 7) await MigrationV7(this).run(m);
        },
        beforeOpen: (details) async {
          // The main isolate and the analysis background isolate each open
          // their own connection to the same file, so enable WAL and a busy
          // timeout to tolerate concurrent readers/writers.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA busy_timeout = 30000');
          await customStatement('PRAGMA foreign_keys = OFF');
        },
      );

  /// Fresh installs must converge on the same index set as upgraded databases.
  ///
  /// Each `MigrationVN` exposes `createNewIndexes()`; call them here as new
  /// versions introduce indexes.
  Future<void> _createIndexes() async {
    await MigrationV3.createNewIndexes(this);
    await MigrationV4.createNewIndexes(this);
    await MigrationV5.createNewIndexes(this);
    await MigrationV7.createNewIndexes(this);
  }
}
