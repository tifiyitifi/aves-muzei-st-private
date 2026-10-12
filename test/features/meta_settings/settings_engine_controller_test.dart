import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/meta_settings/settings_engine_controller.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/settings/store_shared_pref.dart';
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
}
