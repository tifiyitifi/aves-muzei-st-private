import 'package:aves/features/collection_paging/view/clear_filter_button.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/filters/query.dart';
import 'package:aves/model/query.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../common.dart';

/// The clear action at the end of the filter row: one tap leaves the whole
/// library, including the live query that is not a chip.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  tearDown(() async {
    await setUpServices();
  });

  testWidgets('empties the chips and the live query', (tester) async {
    final source = MediaStoreSource()..canAnalyze = false;
    final lens = CollectionLens(
      source: source,
      filters: {StoredAlbumFilter('/album', null), QueryFilter('cat', ACalendar.gregorian, live: true)},
      listenToSource: false,
    );
    addTearDown(lens.dispose);
    final query = Query(enabled: true, initialValue: 'cat');
    addTearDown(query.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<Query>.value(
          value: query,
          child: Scaffold(body: ClearFilterButton(collection: lens)),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('clear-filter-button')));
    await tester.pump();

    expect(lens.filters, isEmpty);
    expect(query.queryNotifier.value, isEmpty, reason: 'the search field is left empty, not showing a stale text');
  });
}
