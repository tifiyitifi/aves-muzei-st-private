import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/meta_settings/store/meta_settings_seeder.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves/model/settings/store_shared_pref.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../helpers/sqlite3_loader.dart';

/// A `MetaSettingsStore` whose [put] starts failing after [failAfter] successes,
/// so a partial seed can be simulated deterministically regardless of the order
/// the legacy keys are iterated in.
class _AbortingMetaStore extends MetaSettingsStore {
  new({required AppDatabase db, this.failAfter}) : super(injectedDatabase: db);

  /// Number of successful puts allowed; every further put fails. `null` never fails.
  int? failAfter;
  int _puts = 0;

  @override
  Future<bool> put(String key, Object? value) {
    final limit = failAfter;
    if (limit != null && _puts >= limit) return Future.value(false);
    _puts++;
    return super.put(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  });

  late AppDatabase db;
  late SharedPrefSettingsStore legacy;

  setUp(() async {
    await (await SharedPreferences.getInstance()).clear();
    db = AppDatabase(NativeDatabase.memory());
    legacy = SharedPrefSettingsStore();
    await legacy.init();
  });

  tearDown(() => db.close());

  Future<bool> isMarked() async {
    final value = (await AppMetaStore(db).read({MetaSettingsSeeder.markerKey}))[MetaSettingsSeeder.markerKey];
    return value == 'true';
  }

  test('a partial seed aborts without the marker and resumes on the next attempt', () async {
    await legacy.setString('a', '1');
    await legacy.setString('b', '2');
    await legacy.setString('c', '3');

    final meta = _AbortingMetaStore(db: db, failAfter: 1);
    await meta.init();

    await MetaSettingsSeeder(legacy: legacy, meta: meta).seedIfNeeded();
    expect(meta.getKeys(), hasLength(1), reason: 'the seed aborted after the first successful write');
    expect(await isMarked(), isFalse, reason: 'a failed seed must not be marked done');

    // the transient failure clears; the next attempt must copy the missing keys
    meta.failAfter = null;
    await MetaSettingsSeeder(legacy: legacy, meta: meta).seedIfNeeded();
    expect(meta.getKeys(), {'a', 'b', 'c'});
    expect(meta.getString('a'), '1');
    expect(meta.getString('b'), '2');
    expect(meta.getString('c'), '3');
    expect(await isMarked(), isTrue);
  });

  test('an already copied key is never overwritten by a retry', () async {
    await legacy.setString('a', 'legacy');
    await legacy.setString('b', '2');

    final meta = MetaSettingsStore(injectedDatabase: db);
    await meta.init();
    // a value already latent in v2 (copied by an earlier attempt, or edited by
    // the user) before the seed completes
    await meta.setString('a', 'v2');

    await MetaSettingsSeeder(legacy: legacy, meta: meta).seedIfNeeded();
    expect(meta.getString('a'), 'v2', reason: 'existing v2 values must win over the legacy seed');
    expect(meta.getString('b'), '2');
    expect(await isMarked(), isTrue);
  });

  test('the marker makes seeding one-shot even if the legacy store changes', () async {
    await legacy.setString('a', '1');

    final meta = MetaSettingsStore(injectedDatabase: db);
    await meta.init();
    await MetaSettingsSeeder(legacy: legacy, meta: meta).seedIfNeeded();
    expect(await isMarked(), isTrue);

    // a later, deliberate v2 clear must not resurrect legacy values
    await legacy.setString('c', '3');
    await meta.clear();
    await MetaSettingsSeeder(legacy: legacy, meta: meta).seedIfNeeded();
    expect(meta.getKeys(), isEmpty);
  });
}
