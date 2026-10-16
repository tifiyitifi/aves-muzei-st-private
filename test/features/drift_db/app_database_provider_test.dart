import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

/// An [AppDatabaseProvider] whose first [AppDatabaseProvider.createDatabase]
/// fails, to exercise [AppDatabaseProvider.open]'s retry. Each successful
/// attempt returns a fresh in-memory database so a reopen after [close] works.
class _FlakyProvider extends AppDatabaseProvider {
  var attempts = 0;

  new();

  @override
  bool get isInjected => true;

  @override
  Future<AppDatabase> createDatabase() async {
    if (attempts++ == 0) throw StateError('transient open failure');
    return AppDatabase(NativeDatabase.memory());
  }
}

void main() {
  setUpAll(ensureSqlite3Loaded);

  test('open returns the same connection to later callers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final provider = AppDatabaseProvider(injected: db);
    addTearDown(provider.close);

    expect(identical(await provider.open(), db), isTrue);
    expect(identical(await provider.open(), db), isTrue);
  });

  test('open retries after a transient failure instead of staying poisoned', () async {
    final provider = _FlakyProvider();
    addTearDown(provider.close);

    await expectLater(provider.open(), throwsA(isA<StateError>()));
    expect(provider.attempts, 1);

    // The failed attempt is dropped, so a later open retries and succeeds.
    final db = await provider.open();
    expect(provider.attempts, 2);
    expect(await db.customSelect('SELECT 1').get(), isNotEmpty);
  });

  test('close drops the cached connection so a later open reopens', () async {
    final provider = _FlakyProvider();
    addTearDown(provider.close);

    await expectLater(provider.open(), throwsA(isA<StateError>()));
    await provider.open();
    expect(provider.attempts, 2);

    await provider.close();
    await provider.open();
    expect(provider.attempts, 3);
  });
}
