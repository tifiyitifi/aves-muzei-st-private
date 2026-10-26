import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/query.dart';
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

/// Album-chip actions adapted to visible-range candidates.
///
/// Layout, sort, title search and selection reuse the album page's delegate.
/// Only rename, delete and "open media set" need feature logic, because a
/// candidate stands for a rule rather than an album.
class VisibleRangeActionDelegate extends ChipSetActionDelegate<VisibleRangeCandidateFilter> {
  final VisibleRangeController controller;
  @override
  final String settingsRouteKey;
  final List<FilterGridItem<VisibleRangeCandidateFilter>> Function() itemBuilder;
  final Future<void> Function(BuildContext context, VisibleRangeRule rule) onRename;
  final Future<void> Function(BuildContext context, Set<VisibleRangeRule> rules) onDelete;
  final Future<void> Function(BuildContext context, VisibleRangeRule rule) onActivate;
  final List<Widget> Function(BuildContext context) extraLayoutRows;

  new({
    required this.controller,
    required this.settingsRouteKey,
    required this.itemBuilder,
    required this.onRename,
    required this.onDelete,
    required this.onActivate,
    required this.extraLayoutRows,
  });

  @override
  Iterable<FilterGridItem<VisibleRangeCandidateFilter>> get allItems => itemBuilder();

  /// The page shows the bundled order instead of offering sorting, so the
  /// layout dialog exposes no sort options. The value only feeds the scrollbar
  /// label, which then names the candidate under the thumb.
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
  List<TileLayout> get layoutOptions => const [
        .mosaic,
        .grid,
        .list,
      ];

  bool _isRule(VisibleRangeCandidateFilter filter) => filter.candidate.rule != null;

  Set<VisibleRangeRule> _selectedRules(BuildContext context) {
    final selection = context.read<Selection<FilterGridItem<VisibleRangeCandidateFilter>>>();
    if (!selection.isSelecting) return {};
    return selection.selectedItems.map((item) => item.filter.candidate.rule).nonNulls.toSet();
  }

  @override
  bool isVisible(
    ChipSetAction action, {
    required AppMode appMode,
    required bool isSelecting,
    required int itemCount,
    required Set<VisibleRangeCandidateFilter> selectedFilters,
  }) {
    final isMain = appMode == AppMode.main;
    final hasSelection = selectedFilters.isNotEmpty;
    final selectedRules = selectedFilters.where(_isRule).length;
    switch (action) {
      case .changeLayout:
        return true;
      case .select:
        return appMode.canSelectFilter && !isSelecting;
      case .selectAll:
        return isSelecting && selectedFilters.length < itemCount;
      case .selectNone:
        return isSelecting && hasSelection;
      case .search:
        return !settings.useTvLayout && appMode.canNavigate && !isSelecting;
      case .toggleTitleSearch:
        return !settings.useTvLayout && !isSelecting;
      case .rename:
        return isMain && isSelecting && selectedRules == 1 && selectedFilters.every(_isRule);
      case .delete:
        return isMain && isSelecting && hasSelection && selectedFilters.every(_isRule);
      case .showCollection:
        return isMain && isSelecting && selectedRules == 1 && selectedFilters.every(_isRule);
      default:
        return false;
    }
  }

  @override
  bool canApply(
    ChipSetAction action, {
    required bool isSelecting,
    required int itemCount,
    required Set<VisibleRangeCandidateFilter> selectedFilters,
  }) {
    switch (action) {
      case .select:
        return itemCount > 0;
      case .changeLayout:
      case .selectAll:
      case .selectNone:
      case .search:
      case .toggleTitleSearch:
        return true;
      case .rename:
      case .showCollection:
        return isSelecting && selectedFilters.length == 1 && selectedFilters.every(_isRule);
      case .delete:
        return isSelecting && selectedFilters.isNotEmpty && selectedFilters.every(_isRule);
      default:
        return false;
    }
  }

  @override
  void onActionSelected(BuildContext context, ChipSetAction action) {
    switch (action) {
      // The album page's search icon opens the media search; here it filters
      // the candidate tiles instead, which is the title query bar.
      case .search:
        context.read<Query>().toggle();
      case .rename:
        final rules = _selectedRules(context);
        if (rules.length == 1) {
          unawaited(onRename(context, rules.first));
          browse(context);
        }
      case .delete:
        final rules = _selectedRules(context);
        if (rules.isNotEmpty) {
          unawaited(onDelete(context, rules));
          browse(context);
        }
      case .showCollection:
        final rules = _selectedRules(context);
        if (rules.length == 1) {
          unawaited(onActivate(context, rules.first));
          browse(context);
        }
      default:
        super.onActionSelected(context, action);
    }
  }

  @override
  Future<void> configureView(BuildContext context) async {
    final initialValue = (
      settings.getTileLayout(settingsRouteKey),
      sortFactor,
      sectionFactor,
      sortReverse,
    );
    final extentController = context.read<TileExtentController>();
    final value = await showAvesDialog<(TileLayout, SortFactor, ChipSectionFactor, bool)>(
      context: context,
      builder: (context) => ChangeLayoutDialog<ChipSectionFactor>(
        initialValue: initialValue,
        layoutOptions: layoutOptions.map((v) => ChangeLayoutDialogOption(value: v, title: v.getName(context), icon: v.icon)).toList(),
        sortOptions: sortOptions.map((v) => ChangeLayoutDialogOption(value: v, title: v.getName(context), icon: v.icon)).toList(),
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
      sectionFactor = value.$3;
      sortReverse = value.$4;
    }
  }
}
