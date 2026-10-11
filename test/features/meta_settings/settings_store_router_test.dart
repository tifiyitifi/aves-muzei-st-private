import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/features/meta_settings/store/settings_store_router.dart';
import 'package:aves/model/settings/store_shared_pref.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    ensureSqlite3Loaded();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  });

  late AppDatabase db;
  late SharedPrefSettingsStore legacy;
  late MetaSettingsStore meta;
  late SettingsEngineGate gate;
  late SettingsStoreRouter router;

  setUp(() async {
    await (await SharedPreferences.getInstance()).clear();
    db = AppDatabase(NativeDatabase.memory());
    legacy = SharedPrefSettingsStore();
    meta = MetaSettingsStore(injectedDatabase: db);
    gate = SettingsEngineGate();
    router = SettingsStoreRouter(legacy: legacy, meta: meta, gate: gate);
  });

  tearDown(() => db.close());

  test('defaults to the metadata engine', () async {
    await router.init();
    expect(router.version, SettingsEngineVersion.v2);
    expect(router.isMeta, isTrue);
  });

  test('the gate selects the legacy engine', () async {
    await gate.write(SettingsEngineVersion.v1);
    await router.init();
    expect(router.version, SettingsEngineVersion.v1);

    await router.setString('k', 'v');
    expect(legacy.getString('k'), 'v');
    expect(meta.getKeys(), isEmpty);
  });

  test('the gate key is hidden from the settings key space', () async {
    await gate.write(SettingsEngineVersion.v1);
    await router.init();

    await router.setString('k', 'v');
    expect(router.getKeys(), {'k'});
    expect(router.getKeys(), isNot(contains(SettingsEngineGate.key)));

    // removing the gate through the store must be a no-op
    await router.remove(SettingsEngineGate.key);
    expect(await gate.read(), SettingsEngineVersion.v1);
  });

  test('clear preserves the gate', () async {
    await gate.write(SettingsEngineVersion.v1);
    await router.init();

    await router.setString('k', 'v');
    await router.clear();

    expect(router.getKeys(), isEmpty);
    expect(await gate.read(), SettingsEngineVersion.v1);
  });

  test('the first metadata init seeds the legacy settings once', () async {
    final pre = SharedPrefSettingsStore();
    await pre.init();
    await pre.setString(SettingKeys.themeBrightnessKey, 'dark');

    await router.init();
    expect(meta.getString(SettingKeys.themeBrightnessKey), 'dark');

    // wiping v2 must not resurrect the legacy values (the marker makes it one-shot)
    await meta.clear();
    final second = SettingsStoreRouter(legacy: legacy, meta: meta, gate: gate);
    await second.init();
    expect(meta.getKeys(), isEmpty);
  });

  test('switching engines keeps the two stores independent after seeding', () async {
    await router.init(); // seeds once (legacy is empty here, so nothing to copy)

    await router.setString('shared', 'v2');
    await router.activate(SettingsEngineVersion.v1);
    await router.setString('shared', 'v1');

    await router.activate(SettingsEngineVersion.v2);
    expect(router.getString('shared'), 'v2');

    await router.activate(SettingsEngineVersion.v1);
    expect(router.getString('shared'), 'v1');
  });
}
