import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_editor_session.dart';
import 'package:aves/features/visible_range/view/visible_range_group_editor_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _RouteCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

/// Every destination the bottom bar can show must resolve to a page.
///
/// `routeBuilder` used to throw `unknown route` for a fork route that had no
/// case, so tapping the wallpaper group entry built nothing and the entry looked
/// dead. The route is built eagerly, which is what this test pins down.
void main() {
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  testWidgets('the wallpaper groups entry opens its page', (tester) async {
    final context = await pumpContext(tester);
    final route = const AvesNavItem(route: GroupedWallpaperPage.routeName).routeBuilder(context, topLevel: false);

    expect(route.settings.name, GroupedWallpaperPage.routeName);
    expect((route as MaterialPageRoute<dynamic>).builder(context), isA<GroupedWallpaperPage>());
  });

  testWidgets('the group editor entry opens its page', (tester) async {
    visibleRangeEditorSession.open('group.test', VisibleRange.emptyGallery());
    addTearDown(visibleRangeEditorSession.close);
    final context = await pumpContext(tester);

    final route = const AvesNavItem(route: VisibleRangeGroupEditorPage.routeName).routeBuilder(context, topLevel: true);

    expect(route.settings.name, VisibleRangeGroupEditorPage.routeName);
    expect((route as MaterialPageRoute<dynamic>).builder(context), isA<VisibleRangeGroupEditorPage>());
  });

  testWidgets('tapping the entry of the page already on top does not stack another one', (tester) async {
    visibleRangeEditorSession.open('group.test', VisibleRange.emptyGallery());
    addTearDown(visibleRangeEditorSession.close);
    final counter = _RouteCounter();
    final navigatorKey = GlobalKey<NavigatorState>();
    late BuildContext editorContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [counter],
        home: const SizedBox(),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: VisibleRangeGroupEditorPage.routeName),
        builder: (context) {
          editorContext = context;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();
    final before = counter.pushes;

    await const AvesNavItem(route: VisibleRangeGroupEditorPage.routeName).goTo(editorContext, topLevel: true);
    await tester.pumpAndSettle();

    expect(counter.pushes, before);
  });
}
