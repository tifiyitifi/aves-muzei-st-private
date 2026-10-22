import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/navigation/drawer/tile.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:material_ui/material_ui.dart';

typedef TileRouteBuilder = Route Function(BuildContext context, String routeName, bool topLevel);

class const PageNavTile({
  super.key,
  final Widget? leading,
  final Widget? title,
  final Widget? trailing,
  required final AvesNavItem navItem,
  final bool Function()? isSelected,
  // Greyed and inert while the browse-only surface cannot serve this page.
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final routeName = navItem.route;
    return SafeArea(
      top: false,
      bottom: false,
      child: ListTile(
        // key is expected by test driver
        key: Key('$routeName-tile'),
        enabled: enabled,
        leading: leading ?? DrawerPageIcon(route: routeName),
        title: title ?? DrawerPageTitle(route: routeName),
        trailing: trailing != null
            ? Builder(
                builder: (context) => DefaultTextStyle.merge(
                  style: TextStyle(
                    color: IconTheme.of(context).color!.withValues(alpha: .6),
                  ),
                  child: trailing!,
                ),
              )
            : null,
        onTap: enabled
            ? () {
                Navigator.maybeOf(context)?.pop();
                navItem.goTo(context);
              }
            : null,
        selected: context.currentRouteName == routeName && (isSelected?.call() ?? true),
      ),
    );
  }
}
