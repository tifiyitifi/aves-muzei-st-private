import 'dart:convert';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/meta_settings/db/settings_dao.dart';
import 'package:aves/features/meta_settings/model/enum/setting_value_type.dart';
import 'package:aves/features/meta_settings/store/meta_settings_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// A DAO whose next [upsert] fails, to exercise a failed write while the
/// database stays readable.
class _FailOnceMetaSettingsDao(super.db) extends MetaSettingsDao {
  bool failNextUpsert = false;

  @override
  Future<void> upsert(String key, SettingValueType type, String raw) {
    if (failNextUpsert) {
      failNextUpsert = false;
      return Future.error(StateError('persistence failure'));
    }
    return super.upsert(key, type, raw);
  }
}

void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late MetaSettingsStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = MetaSettingsStore(injectedDatabase: db);
  });

  tearDown(() => db.close());

  test('typed values round trip through the database', () async {
    await store.init();
    expect(store.initialized, isTrue);

    await store.setBool('b', true);
    await store.setInt('i', -7);
    await store.setDouble('d', 1.5);
    await store.setString('s', 'hello');
    await store.setStringList('l', ['x', 'y']);

    // a fresh store over the same database sees the persisted rows
    final reopened = MetaSettingsStore(injectedDatabase: db);
    await reopened.init();
    expect(reopened.getBool('b'), isTrue);
    expect(reopened.getInt('i'), -7);
    expect(reopened.getDouble('d'), 1.5);
    expect(reopened.getString('s'), 'hello');
    expect(reopened.getStringList('l'), ['x', 'y']);
  });

  test('a value of another type reads back as null', () async {
    await store.init();
    await store.setInt('k', 3);
    expect(store.getBool('k'), isNull);
    expect(store.getString('k'), isNull);
    expect(store.get('k'), 3);
  });

  test('getKeys, remove and clear are persisted', () async {
    await store.init();
    await store.setString('a', '1');
    await store.setString('b', '2');
    expect(store.getKeys(), {'a', 'b'});

    await store.remove('a');
    expect(store.getKeys(), {'b'});

    await store.clear();
    expect(store.getKeys(), isEmpty);

    final reopened = MetaSettingsStore(injectedDatabase: db);
    await reopened.init();
    expect(reopened.getKeys(), isEmpty);
  });

  test('a failed write rolls the cache back instead of diverging', () async {
    await store.init();
    await store.setString('a', 'old');

    // closing the database makes every subsequent persistence attempt fail
    await db.close();

    expect(await store.setString('a', 'new'), isFalse);
    expect(store.getString('a'), 'old', reason: 'cache must not keep an unpersisted value');

    expect(await store.setString('b', 'x'), isFalse);
    expect(store.getKeys(), isNot(contains('b')), reason: 'an unpersisted insert must not linger');

    expect(await store.remove('a'), isFalse);
    expect(store.getString('a'), 'old', reason: 'a failed remove must not drop the cached value');

    expect(await store.clear(), isFalse);
    expect(store.getKeys(), {'a'}, reason: 'a failed clear must not wipe the cache');
  });

  test('put persists a list whose runtime type is not List<String>', () async {
    await store.init();
    final dynamic decoded = jsonDecode('["x","y"]');
    expect(decoded, isNot(isA<List<String>>()), reason: 'guard against the test no longer exercising the narrowing');

    expect(await store.put('l', decoded), isTrue);
    expect(store.getStringList('l'), ['x', 'y']);
  });

  test('put skips a list holding non-string elements without retrying', () async {
    await store.init();
    final dynamic decoded = jsonDecode('[1,2]');
    expect(await store.put('l', decoded), isTrue, reason: 'a permanently unsupported value must not make the seed retry forever');
    expect(store.get('l'), isNull);
  });

  test('a failed write re-syncs the cache to the persisted value', () async {
    final dao = _FailOnceMetaSettingsDao(db);
    final flaky = MetaSettingsStore(injectedDatabase: db, injectedDaoFactory: (_) => dao);
    await flaky.init();
    await flaky.setString('k', 'persisted');

    dao.failNextUpsert = true;
    expect(await flaky.setString('k', 'unpersisted'), isFalse);
    expect(flaky.getString('k'), 'persisted', reason: 'the cache must reflect what the database actually holds');
  });

  test('a failed write does not clobber a later concurrent write to the same key', () async {
    final dao = _FailOnceMetaSettingsDao(db);
    final flaky = MetaSettingsStore(injectedDatabase: db, injectedDaoFactory: (_) => dao);
    await flaky.init();

    dao.failNextUpsert = true;
    final first = flaky.setString('k', 'first'); // fails
    final second = flaky.setString('k', 'second'); // succeeds

    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(flaky.getString('k'), 'second', reason: 'the later write must win in the cache');

    final reopened = MetaSettingsStore(injectedDatabase: db);
    await reopened.init();
    expect(reopened.getString('k'), 'second', reason: 'the cache must match the database');
  });
}
