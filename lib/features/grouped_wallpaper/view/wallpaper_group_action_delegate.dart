import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/selection.dart';
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
class WallpaperGroupActionDelegate extends ChipSetActionDelegate<CollectionFilter> {
  @override
  final String settingsRouteKey;

  final Iterable<FilterGridItem<CollectionFilter>> Function() itemBuilder;
  final List<Widget> Function(BuildContext context) extraLayoutRows;
  final Future<void> Function(BuildContext context, VisibleRangeRule rule) onRename;

  new({
    required this.settingsRouteKey,
    required this.itemBuilder,
    required this.extraLayoutRows,
    required this.onRename,
  });

  @override
  Iterable<FilterGridItem<CollectionFilter>> get allItems => itemBuilder();

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

  static VisibleRangeRule? _ruleOf(CollectionFilter filter) => filter is VisibleRangeCandidateFilter ? filter.candidate.rule : null;

  @override
  bool isVisible(
    ChipSetAction action, {
    required AppMode appMode,
    required bool isSelecting,
    required int itemCount,
    required Set<CollectionFilter> selectedFilters,
  }) {
    final selectedRules = selectedFilters.map(_ruleOf).nonNulls.toList();
    final onlyRules = selectedFilters.isNotEmpty && selectedRules.length == selectedFilters.length;
    return switch (action) {
      // Selection is allowed here too: a rule can be taken out to the media set
      // or deleted from the wallpaper page, exactly like on the range page.
      // Rename is the page's only "modify": conditions themselves are added by
      // pinning from a media set, never edited into existence here.
      .changeLayout || .search || .toggleTitleSearch || .select || .selectAll || .selectNone => super.isVisible(
          action,
          appMode: appMode,
          isSelecting: isSelecting,
          itemCount: itemCount,
          selectedFilters: selectedFilters,
        ),
      .rename => isSelecting && selectedRules.length == 1 && onlyRules,
      _ => false,
    };
  }

  @override
  bool canApply(
    ChipSetAction action, {
    required bool isSelecting,
    required int itemCount,
    required Set<CollectionFilter> selectedFilters,
  }) {
    if (action != .rename) return super.canApply(action, isSelecting: isSelecting, itemCount: itemCount, selectedFilters: selectedFilters);
    final selectedRules = selectedFilters.map(_ruleOf).nonNulls.toList();
    final onlyRules = selectedFilters.isNotEmpty && selectedRules.length == selectedFilters.length;
    return isSelecting && selectedRules.length == 1 && onlyRules;
  }

  @override
  void onActionSelected(BuildContext context, ChipSetAction action) {
    if (action == .rename) {
      final rule = _ruleOf(context.read<Selection<FilterGridItem<CollectionFilter>>>().selectedItems.first.filter);
      if (rule != null) {
        unawaited(onRename(context, rule));
        browse(context);
      }
      return;
    }
    super.onActionSelected(context, action);
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
