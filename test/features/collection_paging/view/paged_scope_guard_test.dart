import 'package:aves/features/collection_paging/engine/collection_engine.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/query/collection_window_predicate.dart';
import 'package:aves/features/collection_paging/view/paged_scope_guard.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/filter_summary_provider.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../common.dart';

/// The guard between an album-grid action and an entry-free (paged) source.
///
/// A paged view keeps no entries in memory, so an action that reads the source
/// either reads the database or must be refused. Acting silently on nothing is
/// the failure this file exists to prevent.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  late _CountingDb database;
  late MediaStoreSource source;

  setUp(() async {
    await setUpServices();
    database = _CountingDb();
    // Bind the app-wide seam to this fake before `localMediaDb` is first read.
    getIt.unregister<LocalMediaDb>();
    getIt.registerSingleton<LocalMediaDb>(database);

    source = MediaStoreSource();
    source.summaries = null;

    await collectionPagingPrefs.setEngine(CollectionEngine.auto);
    await collectionPagingPrefs.setLargeThreshold(20000);
    await collectionPagingPrefs.setImportComplete(true);
  });

  Widget wrap(Future<void> Function(BuildContext context) action) => MultiProvider(
    providers: [
      Provider<CollectionSource>.value(value: source),
      ChangeNotifierProvider<Settings>.value(value: settings),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => action(context),
            child: const Text('run'),
          ),
        ),
      ),
    ),
  );

  testWidgets('an attached summary provider means the action reads the database', (tester) async {
    source.summaries = _FakeSummaries();
    // A small library would otherwise take the in-memory path.
    database.count = 0;

    bool? usesDatabase;
    await tester.pumpWidget(wrap((context) async => usesDatabase = await albumActionUsesDatabase(context)));
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(usesDatabase, isTrue);
  });

  testWidgets('an unfinished import cannot be served from memory', (tester) async {
    await collectionPagingPrefs.setImportComplete(false);

    bool? usesDatabase;
    await tester.pumpWidget(wrap((context) async => usesDatabase = await albumActionUsesDatabase(context)));
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(usesDatabase, isTrue);
  });

  testWidgets('a small finished library keeps the in-memory path', (tester) async {
    database.count = 5;

    bool? usesDatabase;
    await tester.pumpWidget(wrap((context) async => usesDatabase = await albumActionUsesDatabase(context)));
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(usesDatabase, isFalse);
  });

  testWidgets('an action that cannot be served warns instead of acting on nothing', (tester) async {
    await collectionPagingPrefs.setImportComplete(false);

    bool? stop;
    await tester.pumpWidget(wrap((context) async => stop = await pagedScopeUnsupported(context)));
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not available for very large collections'), findsOneWidget);

    // The guard returns only once the user has seen and dismissed the warning.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(stop, isTrue);
  });

  testWidgets('a servable action shows no warning', (tester) async {
    database.count = 5;

    bool? stop;
    await tester.pumpWidget(wrap((context) async => stop = await pagedScopeUnsupported(context)));
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();

    expect(stop, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

class _CountingDb extends Fake implements LocalMediaDb {
  int count = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int> countEntries([CollectionWindowPredicate predicate = const CollectionWindowPredicate()]) async => count;
}

class _FakeSummaries extends Fake implements FilterSummaryProvider;
