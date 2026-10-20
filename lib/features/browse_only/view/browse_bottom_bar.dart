import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/bars/floating_bar.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/extensions/media_query.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_bar/nav_bar.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// What the browse-only surface is showing.
enum BrowseView { timeline, albums, videos }

/// The bottom bar while the browser is the library surface.
///
/// It keeps the user's own navigation bar untouched — same items, same order,
/// same icons and labels — and only changes what a tap opens: an item the
/// browser can serve selects the matching browse view, anything that needs the
/// catalogued library stays visible but greyed. Rewriting the bar would have
/// been a silent settings change, and hiding an item would have been worse.
class BrowseOnlyBottomBar extends StatelessWidget {
  final BrowseView view;
  final ValueChanged<BrowseView> onSelect;

  const new({
    super.key,
    required this.view,
    required this.onSelect,
  });

  /// The view an item asks for, or null when it needs catalogued data.
  static BrowseView? viewFor(AvesNavItem item) {
    if (item.route == AlbumListPage.routeName) return BrowseView.albums;
    if (item.route != CollectionPage.routeName) return null;
    final filters = item.filters ?? const <CollectionFilter>{};
    if (filters.isEmpty) return BrowseView.timeline;
    if (filters.length == 1 && filters.first == MimeFilter.video) return BrowseView.videos;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final items = context.select<Settings, List<AvesNavItem>>((v) => v.bottomNavigationActions);
    if (items.length < 2) return const SizedBox();
    final safeBottomPadding = MediaQuery.of(context).safeBottomPadding;
    final views = [for (final item in items) viewFor(item)];
    final currentIndex = views.indexOf(view);
    return SafeArea(
      bottom: false,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: AppBottomNavBar.getMargin(safeBottomPadding),
          child: AvesFloatingBar(
            margin: EdgeInsets.zero,
            builder: (context, backgroundColor, child) => BottomNavigationBar(
              items: [
                for (var i = 0; i < items.length; i++)
                  BottomNavigationBarItem(
                    icon: views[i] == null ? Opacity(opacity: .35, child: items[i].getIcon(context)) : items[i].getIcon(context),
                    label: items[i].getText(context),
                    tooltip: items[i].getText(context),
                  ),
              ],
              onTap: (index) {
                final target = views[index];
                if (target == null) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(context.l10n.browseOnlyUnavailable)),
                  );
                  return;
                }
                onSelect(target);
              },
              // An item the user removed from the bar leaves no current entry;
              // the first item then carries the highlight instead of all of them.
              currentIndex: currentIndex < 0 ? 0 : currentIndex,
              type: BottomNavigationBarType.fixed,
              backgroundColor: backgroundColor,
              showSelectedLabels: false,
              showUnselectedLabels: false,
            ),
          ),
        ),
      ),
    );
  }
}
