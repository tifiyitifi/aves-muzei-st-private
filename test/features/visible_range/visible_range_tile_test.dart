import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/highlight.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/colors.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../common.dart';

/// The range tile is also rendered by the pinch-zoom preview, which lives in an
/// `OverlayEntry` outside the page's provider tree, and by the wallpaper page,
/// which provides a differently typed selection. It must therefore never look a
/// page-scoped `Selection` provider up.
class _TestColors extends AvesColorsData {
  @override
  Color get neutral => Colors.black54;

  @override
  Color fromHue(double hue) => Colors.indigo;

  @override
  Color? fromBrandColor(Color? color) => color;
}

/// The range tile must build without a page `Selection` provider, and draw its
/// selection mark from the values it is given.
void main() {
  setUpAll(setUpAllServices);

  tearDownAll(tearDownAllServices);

  VisibleRangeTile tile({bool selecting = false, bool selected = false}) {
    return VisibleRangeTile(
      gridItem: FilterGridItem(VisibleRangeCandidateFilter(VisibleRangeCandidate.unrestricted), null),
      stats: null,
      tileLayout: TileLayout.grid,
      tileSize: const Size(120, 120),
      selectable: true,
      selecting: selecting,
      selected: selected,
      onTap: () {},
    );
  }

  VisibleRangeTile groupTile({required bool active}) {
    final group = VisibleRange(
      id: 'group.trips',
      scope: VisibleRangeScope.gallery,
      ownerId: 'group.trips',
      name: 'Trips',
    );
    return VisibleRangeTile(
      gridItem: FilterGridItem(
        VisibleRangeCandidateFilter(VisibleRangeCandidate.fromGroup(group, active: active)),
        null,
      ),
      stats: null,
      tileLayout: TileLayout.grid,
      tileSize: const Size(120, 120),
      selectable: true,
      onTap: () {},
    );
  }

  double groupTileOpacity(WidgetTester tester) {
    final opacities = tester.widgetList<Opacity>(
      find.ancestor(of: find.byType(AvesFilterChip), matching: find.byType(Opacity)),
    );
    return opacities.first.opacity;
  }

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<Settings>.value(value: settings),
          Provider<AvesColorsData>.value(value: _TestColors()),
          ChangeNotifierProvider<HighlightInfo>(create: (_) => HighlightInfo()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('renders without a page Selection provider', (tester) async {
    await tester.pumpWidget(wrap(tile()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(VisibleRangeTile), findsOneWidget);
  });

  testWidgets('draws its own selection badge', (tester) async {
    await tester.pumpWidget(wrap(tile(selecting: true, selected: true)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(AIcons.selected), findsOneWidget);
  });

  testWidgets('a tile that is not selected shows the hollow mark while selecting', (tester) async {
    await tester.pumpWidget(wrap(tile(selecting: true)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(AIcons.unselected), findsOneWidget);
    expect(find.byIcon(AIcons.selected), findsNothing);
  });

  testWidgets('no mark is drawn outside selection mode', (tester) async {
    await tester.pumpWidget(wrap(tile()));
    await tester.pumpAndSettle();

    expect(find.byIcon(AIcons.selected), findsNothing);
    expect(find.byIcon(AIcons.unselected), findsNothing);
  });

  testWidgets('a group that is not current is dimmed like a switched-off condition', (tester) async {
    await tester.pumpWidget(wrap(groupTile(active: false)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(groupTileOpacity(tester), closeTo(.62, .001));
  });

  testWidgets('the current group is drawn at full opacity', (tester) async {
    await tester.pumpWidget(wrap(groupTile(active: true)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(groupTileOpacity(tester), 1);
  });
}
