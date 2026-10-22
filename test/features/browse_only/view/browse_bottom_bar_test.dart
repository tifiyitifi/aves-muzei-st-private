import 'package:aves/features/browse_only/view/browse_bottom_bar.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../common.dart';

/// The browse-only bar is fixed: photos and albums work, videos and favourites
/// stay visible but take no tap at all while the library is being organized.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  testWidgets('videos and favourites are greyed and take no tap', (tester) async {
    var selected = BrowseView.timeline;
    var selections = 0;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<Settings>.value(
          value: settings,
          child: Scaffold(
            bottomNavigationBar: StatefulBuilder(
              builder: (context, setState) => BrowseOnlyBottomBar(
                view: selected,
                onSelect: (view) {
                  selections++;
                  setState(() => selected = view);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(tester.element(find.byType(BrowseOnlyBottomBar)))!;
    final videos = find.text(l10n.browseOnlyVideosTab);
    final favourites = find.text(l10n.drawerCollectionFavourites);
    final albums = find.text(l10n.browseOnlyAlbumsTab);

    // The bar keeps every entry: the two that need the catalogued library are
    // dimmed, not removed.
    expect(find.text(l10n.browseOnlyTimelineTab), findsOneWidget);
    expect(albums, findsOneWidget);
    expect(videos, findsOneWidget);
    expect(favourites, findsOneWidget);

    // An unavailable entry has no ink response at all, so it cannot even show
    // the ripple of a tap that would not do anything.
    expect(find.ancestor(of: albums, matching: find.byType(InkResponse)), findsOneWidget);
    expect(find.ancestor(of: videos, matching: find.byType(InkResponse)), findsNothing);
    expect(find.ancestor(of: favourites, matching: find.byType(InkResponse)), findsNothing);

    await tester.tap(videos);
    await tester.tap(favourites);
    await tester.pump();
    expect(selections, 0);
    expect(selected, BrowseView.timeline);

    // The available entry still switches the view.
    await tester.tap(albums);
    await tester.pump();
    expect(selections, 1);
    expect(selected, BrowseView.albums);
  });
}
