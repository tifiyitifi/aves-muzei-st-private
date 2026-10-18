import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/stats/paged_stats_source.dart';
import 'package:aves/model/device.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/add_shortcut_dialog.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/explorer/explorer_page.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/chip.dart';
import 'package:aves/widgets/stats/stats_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class ExplorerActionDelegate with FeedbackMixin {
  final VolumeRelativeDirectory directory;

  new({required this.directory});

  bool isVisible(
    ExplorerAction action, {
    required AppMode appMode,
  }) {
    final isMain = appMode == .main;
    final useTvLayout = settings.useTvLayout;
    switch (action) {
      case .addShortcut:
        return isMain && device.canPinShortcut;
      case .setHome:
        return isMain && !useTvLayout;
      case .hide:
      case .stats:
        return isMain;
    }
  }

  bool canApply(ExplorerAction action) {
    switch (action) {
      case .addShortcut:
      case .setHome:
      case .hide:
      case .stats:
        return true;
    }
  }

  void onActionSelected(BuildContext context, ExplorerAction action) {
    reportService.log('$runtimeType handles $action');
    switch (action) {
      case .addShortcut:
        _addShortcut(context);
      case .setHome:
        _setHome(context);
      case .hide:
        _hide(context);
      case .stats:
        _goToStats(context);
    }
  }

  PathFilter _getPathFilter() => PathFilter(directory.dirPath);

  Future<void> _addShortcut(BuildContext context) async {
    final filter = _getPathFilter();
    final defaultName = filter.getLabel(context);
    // Windowed like the collection page: the cover picker renders a grid, and a
    // plain lens would be empty on a huge library (entry-free source).
    final collection = PagedCollectionLens(
      source: context.read<CollectionSource>(),
      filters: {filter},
    );

    final result = await showAvesDialog<(AvesEntry?, String)>(
      context: context,
      builder: (context) => AddShortcutDialog(
        defaultName: defaultName,
        collection: collection,
      ),
      routeSettings: const RouteSettings(name: AddShortcutDialog.routeName),
    );
    if (result == null) return;

    final (coverEntry, name) = result;
    if (name.isEmpty) return;

    await appService.pinToHomeScreen(name, coverEntry, route: ExplorerPage.routeName, path: filter.path);
    if (!device.showPinShortcutFeedback) {
      showFeedback(context, FeedbackType.info, context.l10n.genericSuccessFeedback);
    }
  }

  void _setHome(BuildContext context) async {
    settings.setHome(HomePageSetting.explorer, customExplorerPath: directory.dirPath);
    showFeedback(context, FeedbackType.info, context.l10n.genericSuccessFeedback);
  }

  void _hide(BuildContext context) {
    final chipActionDelegate = ChipActionDelegate();
    const action = ChipAction.hide;
    final pathFilter = _getPathFilter();
    if (chipActionDelegate.isVisible(action, filter: pathFilter)) {
      chipActionDelegate.onActionSelected(context, pathFilter, action);
    }
  }

  void _goToStats(BuildContext context) {
    final source = context.read<CollectionSource>();
    final filters = {_getPathFilter()};
    // The scope is entry-free on a huge library, so its stats are folded from
    // the database rather than from an empty lens.
    unawaited(_openStats(context, source, filters));
  }

  Future<void> _openStats(BuildContext context, CollectionSource source, Set<CollectionFilter> filters) async {
    final pagedStats = await pagedStatsSourceFor(filters);
    if (!context.mounted) return;
    final entries = pagedStats != null ? const <AvesEntry>{} : CollectionLens(source: source, filters: filters).sortedEntries.toSet();

    Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: StatsPage.routeName),
        builder: (context) => StatsPage(
          entries: entries,
          source: source,
          pagedStats: pagedStats,
        ),
      ),
    );
  }
}
