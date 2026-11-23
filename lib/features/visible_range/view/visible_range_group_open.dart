import 'dart:async';

import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_editor_session.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_group_editor_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter/widgets.dart';

/// Opens the editor for one gallery group.
///
/// The page follows the wallpaper page's navigation behaviour: in the shared
/// mode it replaces the visible-range entry in place, and with a separate entry
/// it opens on the configured side of the bar. Group 0 never opens: it is
/// 「Unrestricted」 and has nothing to edit.
Future<void> openVisibleRangeGroupEditor(BuildContext context, {required String groupId}) async {
  final group = visibleRangeController.galleryGroupById(groupId);
  if (group == null || visibleRangeController.isGroupZero(groupId)) return;
  if (!visibleRangeController.canEditGroup(groupId)) return;
  visibleRangeEditorSession.open(groupId, group);
  if (groupedWallpaperNavController.mode == GroupedWallpaperNavMode.shared) {
    visibleRangeDestination.value = VisibleRangeDestination.editor;
    return;
  }
  await const AvesNavItem(route: VisibleRangeGroupEditorPage.routeName).goTo(context, topLevel: true);
}
