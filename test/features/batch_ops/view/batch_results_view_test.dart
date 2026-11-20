import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/features/batch_ops/services/batch_service.dart';
import 'package:aves/features/batch_ops/view/batch_results_banner.dart';
import 'package:aves/features/batch_ops/view/batch_results_page.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/drift_local_media_db.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_fetch_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../common.dart';
import '../../../helpers/sqlite3_loader.dart';

/// The results surfaces only ever act on rows the app recorded, and never offer
/// to delete the file: deleting is the album's job, not a batch decision.
///
/// Every database call stays inside the test body: the in-memory connection is
/// opened in the same zone that writes to it, which is what keeps Drift's locks
/// out of a zone mismatch under the widget tester's fake async.
void main() {
  late AppDatabase db;
  late AppDatabaseProvider provider;
  late DriftLocalMediaDb mediaDb;
  late _FakeMediaFetch fetch;
  late BatchResultsService service;

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
    mediaDb = DriftLocalMediaDb(database: db);
    fetch = _FakeMediaFetch();
    service = BatchResultsService(
      provider: provider,
      native: _FakeBatchService(),
      db: mediaDb,
      fetch: fetch,
    );
    getIt.registerSingleton<AppDatabaseProvider>(provider);
    // The results page looks its thumbnails up through the app-wide entry table.
    getIt.unregister<LocalMediaDb>();
    getIt.registerSingleton<LocalMediaDb>(mediaDb);
  });

  tearDown(() async {
    getIt.unregister<AppDatabaseProvider>();
  });

  Future<void> seedPendingResult() async {
    await mediaDb.init();
    await (await service.store()).insertResult(
      BatchResult(
        id: 'job-0',
        jobId: 'job',
        sourceEntryId: 1,
        sourceUri: 'content://media/1',
        sourcePath: '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
        sourceDirectory: '/storage/emulated/0/DCIM/Camera',
        sourceName: 'IMG_0001.jpg',
        resultUri: 'content://media/200',
        resultPath: '/storage/emulated/0/Pictures/aves_batch_results/IMG_0001.jpg',
        resultFileName: 'IMG_0001.jpg',
        resultMimeType: 'image/jpeg',
        resultSizeBytes: 100,
        actionsJson: '[]',
        createdAt: DateTime(2026),
        status: BatchResultStatus.pending,
      ),
    );
    // The scanner has the file, so the row is not mistaken for a missing result.
    fetch.entries['content://media/200'] = _entry(200, 'content://media/200', '/storage/emulated/0/Pictures/aves_batch_results/IMG_0001.jpg');
  }

  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  testWidgets('not now hides the banner and keeps the rows pending', (tester) async {
    await seedPendingResult();
    await tester.pumpWidget(wrap(CustomScrollView(slivers: [BatchResultsBannerSliver(service: service)])));
    await tester.pumpAndSettle();

    expect(find.text('1 result waiting'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    // Hiding is not a decision: nothing was applied and the row is still there.
    expect(find.text('1 result waiting'), findsNothing);
    expect(await (await service.store()).getPending(), hasLength(1));
  });

  testWidgets('the menu offers no delete action', (tester) async {
    await seedPendingResult();
    await tester.pumpWidget(wrap(BatchResultsPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Replace original'), findsOneWidget);
    expect(find.text('Move to source folder'), findsOneWidget);
    expect(find.text('DELETE'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}

AvesEntry _entry(int id, String uri, String path) {
  return AvesEntry(
    id: id,
    uri: uri,
    path: path,
    contentId: id,
    pageId: null,
    sourceMimeType: 'image/jpeg',
    width: 10,
    height: 20,
    sourceRotationDegrees: 0,
    sizeBytes: 5,
    sourceTitle: '$id',
    dateAddedSecs: 1,
    dateModifiedMillis: 2,
    sourceDateTakenMillis: 3,
    durationMillis: 0,
    trashed: false,
    origin: EntryOrigins.mediaStoreContent,
  );
}

class _FakeMediaFetch extends Fake implements MediaFetchService {
  final Map<String, AvesEntry> entries = {};

  @override
  Future<AvesEntry?> getEntry(String uri, String? mimeType, {bool allowUnsized = false}) async => entries[uri];
}

class _FakeBatchService extends Fake implements BatchService {
  @override
  Stream<BatchEvent> run(BatchJob job) => const Stream.empty();

  @override
  Future<void> cancel(String jobId) async {}
}
