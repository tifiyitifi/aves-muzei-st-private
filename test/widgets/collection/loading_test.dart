import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/widgets/collection/loading.dart';
import 'package:aves/widgets/common/providers/durations_provider.dart';
import 'package:aves/widgets/common/providers/media_query_data_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../common.dart';

/// The loading body reports what is happening: the spinner alone cannot say
/// whether the app is working or frozen.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDown(() async {
    await setUpServices();
  });

  Widget app({required MediaStoreSource source, PagedCollectionLens? collection}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Settings>.value(value: settings),
        DurationsProvider(),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQueryDataProvider(
          child: Scaffold(
            body: LoadingEmptyContent(
              source: source,
              collection: collection,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('reports how long the view has been waiting', (tester) async {
    final source = MediaStoreSource()..canAnalyze = false;

    await tester.pumpWidget(app(source: source));
    await tester.pump(const Duration(seconds: 1));

    // The clock is the one figure that is always available, and it moves.
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('Retry'), findsNothing, reason: 'a one-second wait is not escalated');
  });

  testWidgets('offers a retry once a wait with nothing countable behind it drags on', (tester) async {
    final source = MediaStoreSource()..canAnalyze = false;
    // The wait under test is the one with no import behind it: mark the library
    // complete so mounting the lens does not start one.
    await collectionPagingPrefs.init();
    await collectionPagingPrefs.setImportComplete(true);
    final lens = PagedCollectionLens(source: source, filters: {});
    addTearDown(lens.dispose);

    await tester.pumpWidget(app(source: source, collection: lens));
    await tester.pump(const Duration(seconds: 11));

    expect(find.textContaining('Taking longer than usual', findRichText: true), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget, reason: 'the view can always be asked to resolve again');

    // The staggered entrance has to finish before the button accepts a tap.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pump();
  });
}
