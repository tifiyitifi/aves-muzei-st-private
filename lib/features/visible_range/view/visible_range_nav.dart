import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';

/// The bottom-bar destinations a surface should show: the user's own list plus
/// the fork's fixed visible-range destination at the far right.
///
/// The bar is driven by the editable `bottomNavigationActions` setting, so the
/// destination is appended at build time rather than written into the user's
/// settings. When the user already added it, nothing is appended twice.
List<AvesNavItem> withVisibleRangeDestination(List<AvesNavItem> configured, {bool include = true}) {
  if (!include) return configured;
  if (configured.any((item) => item.route == VisibleRangePage.routeName)) return configured;
  return [...configured, const AvesNavItem(route: VisibleRangePage.routeName)];
}
