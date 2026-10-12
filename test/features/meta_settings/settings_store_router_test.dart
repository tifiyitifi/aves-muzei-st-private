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

/// A `MetaSettingsStore` whose [init] fails, to exercise a failed engine switch.
class _ThrowingMetaStore extends MetaSettingsStore {
  @override
  Future<void> init() async => throw StateError('database unavailable');
}

/// A gate whose [write] never succeeds, to exercise a lost selector.
class _FailingGate extends SettingsEngineGate {
  @override
  Future<bool> write(SettingsEngineVersion version) async => false;
}

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

  test('a metadata init failure falls back to the legacy engine for the session', () async {
    await gate.write(SettingsEngineVersion.v2);
    final failing = SettingsStoreRouter(legacy: legacy, meta: _ThrowingMetaStore(), gate: gate);

    await failing.init();

    expect(failing.version, SettingsEngineVersion.v1, reason: 'an unopenable database must not take the app down');
    expect(failing.isMeta, isFalse);

    // the fallback is not persisted: a later launch retries the metadata engine
    expect(await gate.read(), SettingsEngineVersion.v2);
  });

  test('a failed gate write aborts the switch and leaves the engine unchanged', () async {
    await gate.write(SettingsEngineVersion.v1);
    final failing = SettingsStoreRouter(legacy: legacy, meta: meta, gate: _FailingGate());
    await failing.init();
    expect(failing.version, SettingsEngineVersion.v1);

    await expectLater(failing.activate(SettingsEngineVersion.v2), throwsA(isA<StateError>()));

    expect(failing.version, SettingsEngineVersion.v1, reason: 'the switch must not commit when the selector cannot be persisted');
    expect(await gate.read(), SettingsEngineVersion.v1, reason: 'the persisted gate must still name the old engine');

    // the legacy store is still the authoritative one
    await failing.setString('k', 'v');
    expect(legacy.getString('k'), 'v');
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

  test('writes to the gate key are ignored by both engines', () async {
    await gate.write(SettingsEngineVersion.v1);
    await router.init();

    // v1: a stray write would land in the same SharedPreferences file as the gate
    await router.setString(SettingsEngineGate.key, SettingsEngineVersion.v2.name);
    expect(legacy.getString(SettingsEngineGate.key), SettingsEngineVersion.v1.name);
    expect(await gate.read(), SettingsEngineVersion.v1);

    // reads hide the gate too: otherwise the shared v1 file would leak it
    expect(router.get(SettingsEngineGate.key), isNull);
    expect(router.getString(SettingsEngineGate.key), isNull);

    // v2: a stray write would otherwise pollute the metadata store
    await router.activate(SettingsEngineVersion.v2);
    await router.setString(SettingsEngineGate.key, 'polluted');
    expect(meta.getKeys(), isEmpty);
    expect(router.get(SettingsEngineGate.key), isNull);
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

  test('seeding never copies the engine gate key into the metadata store', () async {
    // the gate shares the legacy store's SharedPreferences file
    await gate.write(SettingsEngineVersion.v2);
    final pre = SharedPrefSettingsStore();
    await pre.init();
    await pre.setString(SettingKeys.themeBrightnessKey, 'dark');

    await router.init();
    expect(meta.getString(SettingKeys.themeBrightnessKey), 'dark');
    expect(meta.getKeys(), isNot(contains(SettingsEngineGate.key)));
    expect(router.getKeys(), isNot(contains(SettingsEngineGate.key)));
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

  test('a failed switch keeps the gate, the version and the active store on the old engine', () async {
    await gate.write(SettingsEngineVersion.v1);
    final failing = SettingsStoreRouter(legacy: legacy, meta: _ThrowingMetaStore(), gate: gate);
    await failing.init();
    expect(failing.version, SettingsEngineVersion.v1);

    await expectLater(failing.activate(SettingsEngineVersion.v2), throwsA(isA<StateError>()));

    expect(failing.version, SettingsEngineVersion.v1, reason: 'the switch must not commit when the store cannot open');
    expect(await gate.read(), SettingsEngineVersion.v1, reason: 'the persisted gate must not advance either');

    // the legacy store is still the authoritative one
    await failing.setString('k', 'v');
    expect(legacy.getString('k'), 'v');
  });
}
