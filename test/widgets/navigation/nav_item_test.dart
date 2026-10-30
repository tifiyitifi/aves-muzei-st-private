import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Every destination the bottom bar can show must resolve to a page.
///
/// `routeBuilder` used to throw `unknown route` for a fork route that had no
/// case, so tapping the wallpaper group entry built nothing and the entry looked
/// dead. The route is built eagerly, which is what this test pins down.
void main() {
  testWidgets('the wallpaper groups entry opens its page', (tester) async {
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

    final route = const AvesNavItem(route: GroupedWallpaperPage.routeName).routeBuilder(context, topLevel: false);

    expect(route.settings.name, GroupedWallpaperPage.routeName);
    expect((route as MaterialPageRoute<dynamic>).builder(context), isA<GroupedWallpaperPage>());
  });
}
