import 'package:aves/features/browse_only/view/browse_bottom_bar.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/filters/favourite.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../common.dart';

/// The browse-only bar is the user's own navigation bar, in the user's order:
/// the entries it can serve select a browse view, the rest stay visible but
/// greyed and take no tap at all.
void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  final items = [
    const AvesNavItem(route: CollectionPage.routeName),
    AvesNavItem(route: CollectionPage.routeName, filters: {MimeFilter.video}),
    AvesNavItem(route: CollectionPage.routeName, filters: {FavouriteFilter.instance}),
    const AvesNavItem(route: AlbumListPage.routeName),
  ];

  testWidgets('the bar follows the configured order and greys what it cannot serve', (tester) async {
    settings.bottomNavigationActions = items;
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

    final context = tester.element(find.byType(BrowseOnlyBottomBar));
    final labels = [for (final item in items) item.getText(context)];
    final tooltips = [for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip))) tooltip.message];

    // Same items, same order as the bar the user configured — not a fixed set
    // of our own: photos, videos, favourites, albums.
    expect(tooltips, labels);
    expect(tooltips, [
      items[0].getText(context),
      items[1].getText(context),
      items[2].getText(context),
      items[3].getText(context),
    ]);

    // Videos and favourites need catalogued data: they have no ink response at
    // all, so they cannot even show the ripple of a tap that would do nothing.
    expect(find.descendant(of: find.byTooltip(labels[0]), matching: find.byType(InkResponse)), findsOneWidget);
    expect(find.descendant(of: find.byTooltip(labels[1]), matching: find.byType(InkResponse)), findsNothing);
    expect(find.descendant(of: find.byTooltip(labels[2]), matching: find.byType(InkResponse)), findsNothing);
    expect(find.descendant(of: find.byTooltip(labels[3]), matching: find.byType(InkResponse)), findsOneWidget);

    await tester.tap(find.byTooltip(labels[1]));
    await tester.tap(find.byTooltip(labels[2]));
    await tester.pump();
    expect(selections, 0);
    expect(selected, BrowseView.timeline);

    // The album entry still switches the view.
    await tester.tap(find.byTooltip(labels[3]));
    await tester.pump();
    expect(selections, 1);
    expect(selected, BrowseView.albums);
  });
}
