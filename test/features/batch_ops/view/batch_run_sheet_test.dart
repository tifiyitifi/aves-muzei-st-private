import 'dart:convert';

import 'package:aves/features/batch_ops/db/batch_profile_store.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/view/batch_run_sheet.dart';
import 'package:aves/features/batch_ops/view/batch_tool_catalog.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/services/common/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../common.dart';
import '../../../helpers/sqlite3_loader.dart';

/// A profile is a saved chain, not a schema: an action this build no longer
/// offers is dropped, and the rows the sheet does know still run.
///
/// Every database call stays inside the test body: the in-memory connection is
/// opened in the same zone that writes to it, which is what keeps Drift's locks
/// out of a zone mismatch under the widget tester's fake async.
void main() {
  late AppDatabase db;

  setUpAll(() async {
    await setUpAllServices();
    ensureSqlite3Loaded();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    getIt.registerSingleton<AppDatabaseProvider>(AppDatabaseProvider(injected: db));
  });

  tearDown(() async {
    getIt.unregister<AppDatabaseProvider>();
  });

  Widget wrap() => const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BatchRunSheet(entryCount: 1, kind: BatchProfileKind.share),
        ),
      );

  testWidgets('ignores a profile action this build cannot show', (tester) async {
    // The sheet scrolls its tool rows, so a tall surface builds them all and the
    // row count is what the catalog says, not what fits on screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    await BatchProfileStore(db).saveProfile(
      BatchProfile(
        id: 'share-1',
        name: 'Share chain',
        // The second entry is what an older or newer build could have written.
        actionsJson: jsonEncode([
          {'kind': 'rotate', 'settings': {'angle': 180.0}, 'enabled': true},
          {'kind': 'not-a-tool', 'settings': <String, Object?>{}, 'enabled': true},
        ]),
        kind: BatchProfileKind.share,
        sortOrder: 1,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // One row per runnable tool, and only the action this build knows is on.
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList(growable: false);
    expect(switches, hasLength(batchRunnableCatalog.length));
    expect(switches.where((toggle) => toggle.value), hasLength(1));
    expect(find.text('Rotate'), findsOneWidget);

    final runButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Run'));
    expect(runButton.onPressed, isNotNull, reason: 'the rest of the chain still runs');
  });
}
