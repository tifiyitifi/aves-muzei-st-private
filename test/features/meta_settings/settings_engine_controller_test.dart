import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/settings_engine_controller.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/features/meta_settings/store/settings_store_router.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/settings/store_shared_pref.dart';
import 'package:aves_model/aves_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common.dart';
import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(() async {
    ensureSqlite3Loaded();
    await setUpAllServices();
  });

  tearDownAll(tearDownAllServices);

  test('replaying a diff keeps the replayed keys out of the recent list', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final before = SharedPrefSettingsStore();
    await before.init();
    await before.setString('k', 'old');

    final after = MetaSettingsStore(injectedDatabase: db);
    await after.init();
    await after.setString('k', 'new');

    settings.recentSettingKeys = ['sentinel'];

    SettingsEngineController.replayDiff(settings, before, after);

    expect(settings.recentSettingKeys, ['sentinel'], reason: 'a programmatic replay must not be recorded as a recent change');
  });

  test('notifyKeyChange records a recent key by default', () {
    settings.recentSettingKeys = [];

    settings.notifyKeyChange('some_setting', null, 1);

    expect(settings.recentSettingKeys, contains('some_setting'));
  });

  group('setVersion', () {
    late AppDatabase db;
    late SharedPrefSettingsStore legacy;
    late SettingsEngineGate gate;

    setUp(() async {
      await setUpServices();
      db = AppDatabase(NativeDatabase.memory());
      legacy = SharedPrefSettingsStore();
      await legacy.init();
      gate = SettingsEngineGate();
      await gate.write(SettingsEngineVersion.v1);
    });

    tearDown(() async {
      await db.close();
    });

    test('switching to v2 activates the store and replays the differing key', () async {
      await legacy.setBool(SettingKeys.enableBlurEffectKey, false);

      final meta = MetaSettingsStore(injectedDatabase: db);
      await meta.init();
      await meta.setBool(SettingKeys.enableBlurEffectKey, true);

      final router = SettingsStoreRouter(legacy: legacy, meta: meta, gate: gate);
      await router.init();
      final controller = SettingsEngineController(router: router, sanitize: () async {});

      final events = <SettingsChangedEvent>[];
      final subscription = settings.updateStream.listen(events.add);
      addTearDown(subscription.cancel);

      await controller.setVersion(SettingsEngineVersion.v2);

      expect(controller.version, SettingsEngineVersion.v2);
      expect(await gate.read(), SettingsEngineVersion.v2);

      final replayed = events.firstWhere((event) => event.key == SettingKeys.enableBlurEffectKey);
      expect(replayed.oldValue, false);
      expect(replayed.newValue, true);
      expect(
        settings.recentSettingKeys,
        isNot(contains(SettingKeys.enableBlurEffectKey)),
        reason: 'a switch is not a user edit and must not pollute the recent list',
      );
    });

    test('a switch whose store cannot open leaves the previous engine in place', () async {
      // A closed connection makes the incoming metadata store fail to initialize,
      // which is the router's "do not commit the switch" path.
      final closed = AppDatabase(NativeDatabase.memory());
      // Open it first: drift creates the connection lazily, and closing an
      // unopened database would let the later query open it again.
      await closed.customSelect('SELECT 1').get();
      await closed.close();
      final meta = MetaSettingsStore(injectedDatabase: closed);

      final router = SettingsStoreRouter(legacy: legacy, meta: meta, gate: gate);
      await router.init();
      final controller = SettingsEngineController(router: router, sanitize: () async {});

      final keys = <String>[];
      final subscription = settings.updateStream.listen((event) => keys.add(event.key));
      addTearDown(subscription.cancel);

      await controller.setVersion(SettingsEngineVersion.v2);

      expect(controller.version, SettingsEngineVersion.v1);
      expect(await gate.read(), SettingsEngineVersion.v1);
      expect(keys, isEmpty, reason: 'nothing was activated, so nothing was replayed');
    });

    test('selecting the current engine does nothing', () async {
      final meta = MetaSettingsStore(injectedDatabase: db);
      final router = SettingsStoreRouter(legacy: legacy, meta: meta, gate: gate);
      await router.init();
      final controller = SettingsEngineController(router: router, sanitize: () async {});

      final keys = <String>[];
      final subscription = settings.updateStream.listen((event) => keys.add(event.key));
      addTearDown(subscription.cancel);

      await controller.setVersion(SettingsEngineVersion.v1);

      expect(keys, isEmpty);
      expect(await gate.read(), SettingsEngineVersion.v1);
    });
  });
}
