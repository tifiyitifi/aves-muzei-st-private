import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sqlite3_loader.dart';

void main() {
  setUpAll(ensureSqlite3Loaded);

  late AppDatabase db;
  late AppDatabaseProvider provider;
  late BatchSettings settings;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    provider = AppDatabaseProvider(injected: db);
    settings = BatchSettings(provider: provider);
    await settings.ensureLoaded();
  });

  tearDown(() => db.close());

  test('parses only an offered retention value', () {
    expect(BatchSettings.parseShareRetentionDays('0'), 0);
    expect(BatchSettings.parseShareRetentionDays('1'), 1);
    expect(BatchSettings.parseShareRetentionDays('30'), 30);
    expect(BatchSettings.parseShareRetentionDays(null), BatchSettings.defaultShareRetentionDays);
    expect(BatchSettings.parseShareRetentionDays('365'), BatchSettings.defaultShareRetentionDays);
    expect(BatchSettings.parseShareRetentionDays('soon'), BatchSettings.defaultShareRetentionDays);
  });

  test('round-trips the retention choice', () async {
    expect(settings.shareRetentionDays, BatchSettings.defaultShareRetentionDays);

    await settings.setShareRetentionDays(30);

    expect(settings.shareRetentionDays, 30);
    final reloaded = BatchSettings(provider: provider);
    await reloaded.ensureLoaded();
    expect(reloaded.shareRetentionDays, 30);
  });

  test('remembers the share explainer once shown', () async {
    expect(await settings.hasSeenShareIntro(), isFalse);

    await settings.markShareIntroSeen();

    expect(await settings.hasSeenShareIntro(), isTrue);
    final reloaded = BatchSettings(provider: provider);
    expect(await reloaded.hasSeenShareIntro(), isTrue);
  });
}
