import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/tile_extent_controller.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/change_layout_dialog.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/chip_set.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// App bar actions for the wallpaper-group page.
///
/// The page edits conditions instead of albums, so only the browsing actions
/// (layout, media search, title search) apply. Everything that would browse,
/// share or delete entries is hidden: there is no media set to act on.
///
/// Layout is stored under the page's own route key, so the wallpaper page keeps
/// its own layout while the visible-range page keeps another.
class WallpaperGroupActionDelegate extends ChipSetActionDelegate<VisibleRangeCandidateFilter> {
  @override
  final String settingsRouteKey;

  final Iterable<FilterGridItem<VisibleRangeCandidateFilter>> Function() itemBuilder;
  final List<Widget> Function(BuildContext context) extraLayoutRows;

  new({
    required this.settingsRouteKey,
    required this.itemBuilder,
    required this.extraLayoutRows,
  });

  @override
  Iterable<FilterGridItem<VisibleRangeCandidateFilter>> get allItems => itemBuilder();

  @override
  SortFactor get sortFactor => SortFactor.chipName;

  @override
  set sortFactor(SortFactor factor) {}

  @override
  bool get sortReverse => false;

  @override
  set sortReverse(bool value) {}

  @override
  List<SortFactor> get sortOptions => const [];

  @override
  List<TileLayout> get layoutOptions => const [.mosaic, .grid, .list];

  @override
  bool isVisible(
    ChipSetAction action, {
    required AppMode appMode,
    required bool isSelecting,
    required int itemCount,
    required Set<VisibleRangeCandidateFilter> selectedFilters,
  }) {
    return switch (action) {
      // Selection is allowed here too: a rule can be taken out to the media set
      // or deleted from the wallpaper page, exactly like on the range page.
      .changeLayout || .search || .toggleTitleSearch || .select || .selectAll || .selectNone => super.isVisible(
          action,
          appMode: appMode,
          isSelecting: isSelecting,
          itemCount: itemCount,
          selectedFilters: selectedFilters,
        ),
      _ => false,
    };
  }

  @override
  Future<void> configureView(BuildContext context) async {
    final initialValue = (
      settings.getTileLayout(settingsRouteKey),
      sortFactor,
      ChipSectionFactor.none,
      sortReverse,
    );
    final extentController = context.read<TileExtentController>();
    final value = await showAvesDialog<(TileLayout, SortFactor, ChipSectionFactor, bool)>(
      context: context,
      builder: (context) => ChangeLayoutDialog<ChipSectionFactor>(
        initialValue: initialValue,
        layoutOptions: layoutOptions.map((v) => ChangeLayoutDialogOption(value: v, title: v.getName(context), icon: v.icon)).toList(),
        sortOptions: const [],
        sectionOptions: const [],
        sortOrder: (factor, reverse) => factor.getOrderName(context, reverse),
        tileExtentController: extentController,
        extraRows: extraLayoutRows(context),
      ),
      routeSettings: const RouteSettings(name: ChangeLayoutDialog.routeName),
    );
    await Future.delayed(ADurations.dialogTransitionLoose * timeDilation);
    if (value != null && initialValue != value) {
      settings.setTileLayout(settingsRouteKey, value.$1);
      sortFactor = value.$2;
      sortReverse = value.$4;
    }
  }
}
