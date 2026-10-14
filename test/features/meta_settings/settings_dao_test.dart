import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/logging/log_level.dart';
import 'package:aves/features/meta_settings/db/settings_dao.dart';
import 'package:aves/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late MetaSettingsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = MetaSettingsDao(db);
  });

  tearDown(() {
    Log.reset();
    return db.close();
  });

  test('upsert refreshes updatedAt on conflict', () async {
    await dao.upsert('k', SettingValueType.string, 'a');
    // force a distinguishable old timestamp so the assertion does not depend on
    // the clock's (one second) resolution
    await db.customStatement("UPDATE settingsValues SET updated_at = 0 WHERE key = 'k'");

    await dao.upsert('k', SettingValueType.string, 'b');

    final row = await (db.select(db.settingsValuesTable)..where((t) => t.key.equals('k'))).getSingle();
    expect(row.value, 'b');
    expect(row.updatedAt.year, greaterThan(2000), reason: 'a conflicting upsert must refresh updatedAt');
  });

  test('a row with an unreadable type tag is skipped and logged', () async {
    final records = <String>[];
    Log.setSink((key, level, message, error, stackTrace) => records.add('$key|$message'));
    Log.setLevel(LogKeys.settings, LogLevel.warning);

    await db.into(db.settingsValuesTable).insert(SettingsValuesTableCompanion.insert(key: 'bad', type: 'bogus', value: 'x'));

    expect(await dao.loadAll(), isEmpty);
    expect(await dao.load('bad'), isNull);
    expect(records, isNotEmpty, reason: 'an unreadable row must leave a diagnostic trail');
  });

  test('an enumeration tag is unreadable, as the storage path never writes it', () async {
    await db.into(db.settingsValuesTable).insert(SettingsValuesTableCompanion.insert(key: 'e', type: SettingValueType.enumeration.name, value: 'x'));

    expect(await dao.load('e'), isNull);
  });
}
