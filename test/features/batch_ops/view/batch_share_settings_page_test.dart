import 'package:aves/features/batch_ops/db/batch_profile_store.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/view/batch_share_settings_page.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../common.dart';
import '../../../helpers/sqlite3_loader.dart';

/// The share page owns two things the user can only change here: how long the
/// temporary folder keeps a copy, and which share profiles exist.
///
/// Every database call stays inside the test body: the in-memory connection is
/// opened in the same zone that writes to it, which is what keeps Drift's locks
/// out of a zone mismatch under the widget tester's fake async.
void main() {
  late AppDatabase db;
  late AppDatabaseProvider provider;

  setUpAll(() async {
    await setUpAllServices();
    ensureSqlite3Loaded();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    provider = AppDatabaseProvider(injected: db);
    getIt.registerSingleton<AppDatabaseProvider>(provider);
  });

  tearDown(() async {
    getIt.unregister<AppDatabaseProvider>();
  });

  Widget wrap() => const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BatchShareSettingsPage(),
      );

  testWidgets('the retention radio group writes the chosen value', (tester) async {
    await batchSettings.setShareRetentionDays(BatchSettings.defaultShareRetentionDays);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Keep until I delete'), findsOneWidget);
    expect(find.text('After 7 days'), findsOneWidget);

    await tester.tap(find.text('After 1 day'));
    await tester.pumpAndSettle();

    expect(batchSettings.shareRetentionDays, 1);
    // A reload must see the choice, not the in-memory default.
    final reloaded = BatchSettings(provider: provider);
    await reloaded.ensureLoaded();
    expect(reloaded.shareRetentionDays, 1);
  });

  testWidgets('lists only share profiles', (tester) async {
    // The profile list sits below the retention block, so the default 800x600
    // test surface would not build those rows.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = BatchProfileStore(db);
    final now = DateTime.now();
    for (final (id, name, kind) in [
      ('batch-1', 'Batch chain', BatchProfileKind.batch),
      ('share-1', 'Share chain', BatchProfileKind.share),
    ]) {
      await store.saveProfile(
        BatchProfile(
          id: id,
          name: name,
          actionsJson: '[]',
          kind: kind,
          sortOrder: 1,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Share chain'), findsOneWidget);
    expect(find.text('Batch chain'), findsNothing);
  });

  testWidgets('shows the temporary folder the explainer describes', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('Pictures/aves_share'), findsOneWidget);
  });
}
