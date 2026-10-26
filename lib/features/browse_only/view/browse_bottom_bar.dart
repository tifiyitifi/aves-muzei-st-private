import 'package:aves/features/visible_range/view/visible_range_nav.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/bars/floating_bar.dart';
import 'package:aves/widgets/common/extensions/media_query.dart';
import 'package:aves/widgets/filter_grids/albums_page.dart';
import 'package:aves/widgets/navigation/nav_bar/nav_bar.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// What the browse-only surface can show.
///
/// Exactly two things: the timeline and the album list. Both read the media
/// store directly, so neither waits for the catalogued library.
enum BrowseView { timeline, albums }

/// The bottom bar while the browser is the library surface.
///
/// It keeps the user's own navigation bar untouched — same items, same order,
/// same icons — and only changes what a tap opens: an item the browser can serve
/// selects the matching browse view, anything that needs catalogued data stays
/// visible but greyed and takes no tap at all. Greying it says the feature comes
/// back; rewriting or hiding the bar would have been a silent settings change.
class BrowseOnlyBottomBar extends StatelessWidget {
  final BrowseView view;
  final ValueChanged<BrowseView> onSelect;

  const new({
    super.key,
    required this.view,
    required this.onSelect,
  });

  /// The view an item asks for, or null when it needs catalogued data.
  ///
  /// Videos and favourites are collection destinations like any other, but the
  /// browser answers from the media store alone: it can show the whole timeline
  /// and a folder, not a filter over catalogued metadata.
  static BrowseView? viewFor(AvesNavItem item) {
    if (item.route == AlbumListPage.routeName) return BrowseView.albums;
    if (item.route != CollectionPage.routeName) return null;
    final filters = item.filters ?? const <CollectionFilter>{};
    if (filters.isEmpty) return BrowseView.timeline;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.select<Settings, List<AvesNavItem>>((v) => v.bottomNavigationActions);
    if (configured.length < 2) return const SizedBox();
    final items = withVisibleRangeDestination(configured);
    if (items.length < 2) return const SizedBox();
    final views = [for (final item in items) viewFor(item)];
    final safeBottomPadding = MediaQuery.of(context).safeBottomPadding;
    return SafeArea(
      bottom: false,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: AppBottomNavBar.getMargin(safeBottomPadding),
          child: AvesFloatingBar(
            margin: EdgeInsets.zero,
            builder: (context, backgroundColor, child) => Material(
              color: backgroundColor,
              child: SizedBox(
                height: kBottomNavigationBarHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++) Expanded(child: _buildEntry(context, items[i], views[i])),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(BuildContext context, AvesNavItem item, BrowseView? target) {
    final theme = Theme.of(context);
    final label = item.getText(context);
    final selected = target != null && target == view;
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final icon = IconTheme.merge(
      data: IconThemeData(color: color),
      child: item.getIcon(context),
    );
    if (target == null) {
      // Dimmed and inert: no ink response and no tap handler, so the entry
      // cannot even flash a ripple that implies something will happen.
      return Semantics(
        label: label,
        enabled: false,
        child: Tooltip(
          message: label,
          child: Opacity(opacity: .35, child: Center(child: icon)),
        ),
      );
    }
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: () {
          if (!selected) onSelect(target);
        },
        child: Center(child: icon),
      ),
    );
  }
}
