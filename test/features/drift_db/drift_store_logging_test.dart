import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/debug/debug_store.dart';
import 'package:aves/features/drift_db/entries/entry_store.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/logging/log_level.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/sqlite3_loader.dart';

/// The drift stores used to `debugPrint`; they must now emit through the fork
/// logger on [LogKeys.db], so a build can silence them via the channel gate.
void main() {
  setUpAll(() {
    ensureSqlite3Loaded();
    getIt.registerLazySingleton<p.Context>(() => p.Context(style: p.Style.posix));
  });

  tearDownAll(getIt.reset);

  late AppDatabase db;
  late List<({String key, LogLevel level, Object? message})> records;

  setUp(() {
    records = [];
    Log.reset();
    Log.setSink((key, level, message, error, stackTrace) => records.add((key: key, level: level, message: message)));
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    Log.reset();
    await db.close();
  });

  test('an open log.db channel receives store records at debug level', () async {
    Log.setEnabled(LogKeys.db, true);

    await EntryStore(db).clear();
    await DebugStore(db).clear();

    expect(records, hasLength(2));
    expect(records.map((r) => r.key), everyElement(LogKeys.db));
    expect(records.map((r) => r.level), everyElement(LogLevel.debug));
  });

  test('a closed log.db channel receives nothing', () async {
    await EntryStore(db).clear();
    expect(records, isEmpty);
  });
}
