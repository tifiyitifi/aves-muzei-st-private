import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_sections.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_range_controller.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_auto_advance_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_effects_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_gestures_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_history_page.dart';
import 'package:aves/features/grouped_wallpaper/view/grouped_wallpaper_view_page.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_action_delegate.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_filter.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_labels.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_section_key.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_availability_label.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/grouped_wallpaper_history_limit_dialog.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_tile.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_apply.dart';
import 'package:aves/features/visible_range/services/visible_range_candidate_stats.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/features/visible_range/services/visible_range_gate.dart';
import 'package:aves/features/visible_range/view/visible_range_about_page.dart';
import 'package:aves/features/visible_range/view/visible_range_active_footer.dart';
import 'package:aves/features/visible_range/view/visible_range_candidate_filter.dart';
import 'package:aves/features/visible_range/view/visible_range_destination.dart';
import 'package:aves/features/visible_range/view/visible_range_page.dart';
import 'package:aves/features/visible_range/view/visible_range_labels.dart';
import 'package:aves/features/visible_range/view/visible_range_section_key.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_lock_dialog.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_rule_actions.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/scaling.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/common/providers/query_provider.dart';
import 'package:aves/widgets/common/tile_extent_controller.dart';
import 'package:aves/widgets/filter_grids/common/app_bar.dart';
import 'package:aves/widgets/filter_grids/common/filter_grid_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

/// The wallpaper-group page: the visible-range editor with a group switcher on
/// top.
///
/// It reuses the range page's sections, tiles and active footer, but edits the
/// range of the selected wallpaper group (`scope = wallpaper`) instead of the
/// gallery's single range. Its layout, title query, active-style form and group
/// switcher are stored under this page's own keys, so the two pages can look
/// different.
///
/// [routeName] is a settings key only: the page shares the visible-range
/// destination in the bottom bar and is rendered by [VisibleRangeShellPage].
class GroupedWallpaperPage extends StatefulWidget {
  static const routeName = '/wallpaper_groups';

  /// Whether the page opens on the group the wallpaper is playing.
  ///
  /// A wallpaper gesture opens the view page over the playing group's page, so
  /// that page must show what the view is showing rather than the last group the
  /// user browsed. The bottom-bar destination keeps the browsing session instead.
  final bool selectCurrent;

  const new({super.key, this.selectCurrent = false});

  @override
  State<GroupedWallpaperPage> createState() => _GroupedWallpaperPageState();
}

enum _PageAction {
  toggleEnabled,
  moveUp,
  moveDown,
  rename,
  add,
  delete,
  order,
  lock,
  lockDetailed,
  about,
  applyToMediaSet,
  editRule,
  renameRule,
  deleteSelectedConditions,
  deleteSelectedGroups,
  visibleRange,
  toggleNavEntry,
  saveChanges,
  discardChanges,
  syncNow,
  setCurrentAsWallpaper,
  disableWallpaper,
  viewCurrent,
  effects,
  autoAdvance,
  gestures,
  history,
  historyLimit,
  duplicateGroup,
  engineStatus,
  toggleNotification,
  toggleScrollEffect,
  cancelGalleryRange,
}

class _GroupedWallpaperPageState extends State<GroupedWallpaperPage> with WidgetsBindingObserver {
  /// Width of one card of the fixed five-column switcher.
  static const int _grid5ColumnCount = 5;

  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  Map<String, Set<CollectionFilter>> _groupFilters = const {};
  VisibleRangeCandidateStats? _resultStats;
  int _resultToken = 0;

  late final WallpaperGroupRangeController _controller;

  /// The page's multi-selection.
  ///
  /// The page owns it instead of looking it up in the widget tree: the handlers
  /// below run from the `State`'s context, which sits above the provider created
  /// in `build`, so an ancestor lookup would never find it. Holding the instance
  /// also states who is responsible for disposing it.
  ///
  /// `toSelectableItems` is passed explicitly because the model requires the
  /// choice: a grid item is selected as itself. Group cards get a stable key:
  /// their filter carries the async image count and view flags, so keying by the
  /// item would drop a selected group whenever its count refreshes.
  final _selection = Selection<FilterGridItem<CollectionFilter>>(
    toSelectableItems: null,
    keyOf: (item) => item.filter is WallpaperGroupFilter ? 'group:${(item.filter as WallpaperGroupFilter).groupId ?? 'none'}' : item,
  );

  /// The group the current selection was made in.
  String? _selectionGroupId;

  /// Whether the gallery range is temporarily ignored while this page is open.
  ///
  /// It only affects browsing on this page; leaving restores it, and it never
  /// changes the range itself or the wallpaper.
  bool _gallerySuspended = false;

  /// What the live wallpaper last baked, read when the page opens or resumes.
  GroupedWallpaperState? _engineState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WallpaperGroupRangeController();
    _controller.addListener(_onControllerChanged);
    _syncBrowsingOverlay();
    unawaited(_initController());
    unawaited(_refreshEngine());
  }

  /// Loads the groups, then honours [GroupedWallpaperPage.selectCurrent].
  ///
  /// The controller resumes the browsing session or group 1 by default; a page
  /// opened as the backdrop of the wallpaper view starts on the playing group
  /// instead, so the two pages describe the same group.
  Future<void> _initController() async {
    await _controller.init();
    if (!mounted || !widget.selectCurrent) return;
    final current = _controller.current;
    if (current.isNone || _controller.selectedGroupId == current.id) return;
    if (_controller.groups.any((group) => group.id == current.id)) {
      await _controller.selectGroup(current.id);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the page keeps the viewed group's scope for browsing, so the other
    // tabs show exactly what the wallpaper may use. The temporary gallery
    // suspension is page-local and is restored here; selecting group 0 leaves a
    // null scope, which clears the overlay.
    VisibleRangeGate.setWallpaperScope(_controller.range?.resolve());
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _selection.dispose();
    _appBarHeightNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The wallpaper is set from the system chooser, which takes the app to the
    // background: re-probe on return so the menu reflects the new state.
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshEngine());
    // A notification action can switch the current group while the app is in the
    // background, so the page's list is re-read too.
    unawaited(_controller.reloadGroups());
  }

  /// Re-reads whether the grouped wallpaper is active, whether it is turned on,
  /// whether it may show its bar, whether frames pan with the home pages, and
  /// what it is showing.
  Future<void> _refreshEngine() async {
    final active = await wallpaperEngineLink.refreshActive();
    await wallpaperEngineLink.refreshDisabled();
    await wallpaperEngineLink.refreshNotification();
    await wallpaperEngineLink.refreshScrollEffect();
    final state = await wallpaperEngineLink.readState();
    if (!mounted) return;
    setState(() => _engineState = active ? state : null);
    await _warnIfOverwritten(state, active: active);
  }

  /// Warns once when another wallpaper replaced this one.
  ///
  /// The controller keeps the "was the system wallpaper" marker, because a state
  /// file alone cannot tell a replaced wallpaper apart from one that was never
  /// set. The dialog can silence the warning for good; the checkbox starts
  /// checked, so the default answer is "do not nag me again".
  Future<void> _warnIfOverwritten(GroupedWallpaperState? state, {required bool active}) async {
    if (!wallpaperEngineLink.isAttached) return;
    final warn = await _controller.groupController.takeOverwriteWarning(
      active: active,
      disabled: wallpaperEngineLink.isDisabled,
      hasFrame: state?.hasPhoto ?? false,
    );
    if (!warn || !mounted) return;
    final choice = await showDialog<_OverwriteChoice>(
      context: context,
      builder: (context) => const _OverwriteDialog(),
    );
    if (choice == null) return;
    if (choice.dismissForever) {
      await _controller.groupController.dismissOverwriteWarning();
    }
    if (!mounted) return;
    if (choice.reapply) {
      await _setWallpaper();
    }
  }

  /// Turns the wallpaper's notification bar on or off.
  ///
  /// Off drops the foreground service too, so the wallpaper can be reclaimed more
  /// eagerly on some devices: the snackbar offers the documented re-apply instead
  /// of leaving the user with a stopped wallpaper and no hint.
  Future<void> _toggleNotification() async {
    final enabled = !wallpaperEngineLink.notificationEnabled;
    await wallpaperEngineLink.setNotification(enabled);
    await _refreshEngine();
    if (!mounted || enabled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.wallpaperNotificationOffHint),
        action: SnackBarAction(
          label: context.l10n.wallpaperGroupReapply,
          onPressed: () => unawaited(_setWallpaper()),
        ),
      ),
    );
  }

  /// Closes or reopens the bottom bar's own entry for this page.
  ///
  /// Closing removes the entry the page was reached from, so the page hands the
  /// screen back to the visible range it sits next to instead of staying on a
  /// destination the bar no longer shows.
  Future<void> _toggleNavEntry() async {
    final closing = !groupedWallpaperNavController.entryClosed;
    await groupedWallpaperNavController.toggleEntryClosed();
    if (!closing || !mounted) return;
    visibleRangeDestination.value = VisibleRangeDestination.range;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: VisibleRangePage.routeName),
          builder: (_) => const VisibleRangeShellPage(),
        ),
      ),
    );
  }

  /// Turns the home-screen scroll effect on or off.
  ///
  /// Global to the grouped wallpaper: the engine re-bakes the frame on screen so
  /// the change applies at once instead of waiting for the next photo.
  Future<void> _toggleScrollEffect() async {
    final enabled = !wallpaperEngineLink.scrollEffectEnabled;
    await wallpaperEngineLink.setScrollEffect(enabled);
    await _refreshEngine();
  }

  /// Re-bakes the saved frame when the group list or a range changed.
  ///
  /// The engine skips the bake when the frame already matches the saved group,
  /// so this is cheap on an untouched page; when the wallpaper is running it is
  /// also what makes a saved edit show up without a manual sync.
  Future<void> _prepareWallpaper() async {
    if (!wallpaperEngineLink.isAttached) return;
    await wallpaperEngineLink.prepare();
    await _refreshEngine();
  }

  /// Publishes the page's browsing scope: the group on screen joins the gallery
  /// range while the wallpaper page is open. The live wallpaper never uses this;
  /// it reads the saved group range alone.
  void _syncBrowsingOverlay() {
    VisibleRangeGate.overlay = VisibleRangeBrowsingOverlay(
      groupFilter: _controller.range?.resolve(),
      gallerySuspended: _gallerySuspended,
    );
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // A selection only means something inside the group it was made in: the
    // actions below write to the selected group's range, so carrying candidates
    // over to another group would apply or delete them in the wrong place.
    final groupId = _controller.selectedGroupId;
    if (groupId != _selectionGroupId) {
      _selectionGroupId = groupId;
      _selection.browse();
    }
    _syncBrowsingOverlay();
    setState(() {});
    unawaited(_refreshResultStats());
    unawaited(_refreshGroupFilters());
  }

  /// Count and cover of what the selected group's range resolves to.
  Future<void> _refreshResultStats() async {
    final range = _controller.range;
    final token = ++_resultToken;
    if (range == null) {
      setState(() => _resultStats = null);
      return;
    }
    final filter = range.resolve();
    final filters = filter == null ? const <CollectionFilter>{} : <CollectionFilter>{filter};
    final stats = await VisibleRangeCandidateStatsLoader.load([filters]);
    if (!mounted || token != _resultToken) return;
    setState(() => _resultStats = stats.values.firstOrNull);
  }

  /// The media set behind every group card, so a card without a note can show
  /// its image count. Group 0 is every image.
  Future<void> _refreshGroupFilters() async {
    final next = <String, Set<CollectionFilter>>{wallpaperGroupNoneId: {MimeFilter.image}};
    for (final group in _controller.groups) {
      final range = await _controller.groupController.groupRange(group.id);
      final filter = wallpaperMediaSetFilter(range);
      next[group.id] = filter == null ? {MimeFilter.image} : {filter};
    }
    if (!mounted) return;
    setState(() => _groupFilters = next);
    await _refreshStats();
  }

  Future<void> _refreshStats() async {
    final range = _controller.range;
    final filtersByKey = <String, Set<CollectionFilter>>{};
    if (range != null) {
      for (final section in buildWallpaperGroupSections(range: range)) {
        for (final candidate in section.candidates) {
          // Empty-section slots are not conditions: querying the whole library
          // for them would be noise. 「All images」 is a real candidate, so it
          // keeps the images' cover and count the base section shows.
          if (candidate.placeholder) continue;
          filtersByKey.putIfAbsent(candidate.statsKey, () => candidate.filters);
        }
      }
    }
    for (final filters in _groupFilters.values) {
      filtersByKey.putIfAbsent(filterFingerprint(filters), () => filters);
    }
    final missing = filtersByKey.entries
        .where((entry) => !_stats.containsKey(entry.key) && !_pendingStats.contains(entry.key))
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList();
    if (missing.isEmpty) return;
    _pendingStats.addAll(missing.map((entry) => entry.key));
    try {
      await VisibleRangeCandidateStatsLoader.load(
        missing.map((entry) => entry.value),
        onResult: (key, stats) {
          if (!mounted) return;
          setState(() => _stats = {..._stats, key: stats});
        },
      );
    } finally {
      _pendingStats.removeAll(missing.map((entry) => entry.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final source = context.read<CollectionSource>();
        final sections = _buildSections(context);
        final delegate = WallpaperGroupActionDelegate(
          settingsRouteKey: GroupedWallpaperPage.routeName,
          // Only applicable candidates take part in the selection: the result
          // preview and the unrestricted base are shown but cannot be selected,
          // so a "select all" must not pick them up either.
          itemBuilder: () => sections.values.expand((list) => list).where((item) {
            final filter = item.filter;
            return filter is VisibleRangeCandidateFilter && !filter.summary && _isSelectable(filter.candidate);
          }).toList(),
          // The page keeps its own view preferences, so the layout dialog shows
          // the same controls as the visible-range page but writes this page's
          // keys.
          extraLayoutRows: (context) => [_buildActiveStyleRow(context), _buildSwitcherStyleRow(context)],
          onRename: (context, rule) => _renameRule(rule),
        );
        return FilterGroupProvider(
          child: ChangeNotifierProvider<Selection<FilterGridItem<CollectionFilter>>>.value(
            value: _selection,
            child: Builder(
              builder: (context) {
                final scrollController = PrimaryScrollController.of(context);
                return QueryProvider(
                  startEnabled: settings.getShowTitleQuery(GroupedWallpaperPage.routeName),
                  child: FilterGridPage<CollectionFilter>(
                    settingsRouteKey: GroupedWallpaperPage.routeName,
                    appBar: FilterGridAppBar<CollectionFilter, WallpaperGroupActionDelegate>(
                      source: source,
                      title: context.l10n.wallpaperGroupsTitle,
                      titleStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0,
                        fontFeatures: const [],
                      ),
                      actionDelegate: delegate,
                      extraActionsBuilder: _buildExtraActions,
                      extraMenuEntriesBuilder: _buildExtraMenuEntries,
                      onExtraMenuSelected: (value) {
                        if (value is _PageAction) unawaited(_onMenuSelected(value));
                      },
                      appBarHeightNotifier: _appBarHeightNotifier,
                      scrollController: scrollController,
                      onGroupCrumbTap: (context, filter) {},
                    ),
                    appBarHeightNotifier: _appBarHeightNotifier,
                    scrollController: scrollController,
                    sections: sections,
                    newFilters: const {},
                    sortFactor: delegate.sortFactor,
                    showHeaders: true,
                    selectable: true,
                    // The section mode already lays the groups out in the grid.
                    headerBuilder: _controller.switcherStyle == WallpaperGroupSwitcherStyle.sections ? null : _buildGroupSwitcher,
                    emptyBuilder: _buildEmpty,
                    heroType: HeroType.never,
                    onTileTap: (item, navigate) => _onTileTap(item),
                    selectableItem: (item) {
                      final filter = item.filter;
                      if (filter is WallpaperGroupFilter) return filter.groupId != null;
                      return filter is VisibleRangeCandidateFilter && !filter.summary && _isSelectable(filter.candidate);
                    },
                    tileBuilder: _buildTile,
                    footerBuilder: _controller.activeStyle == VisibleRangeActiveStyle.section ? null : _buildFooter,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    final l10n = context.l10n;
    if (_controller.loading) return const Center(child: CircularProgressIndicator());
    if (_controller.groups.isEmpty) return Center(child: Text(l10n.wallpaperGroupsEmpty));
    if (_controller.selectedGroupId == null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(l10n.wallpaperGroupNoneBody, textAlign: TextAlign.center)));
    return Center(child: Text(l10n.visibleRangeNoCandidates));
  }

  // group switcher

  /// The switcher pinned above the sections in the chips and five-column modes.
  ///
  /// It selects which group's range is shown; it never changes the wallpaper's
  /// current group, which is a group action and belongs to the group menu.
  Widget _buildGroupSwitcher(BuildContext context) {
    switch (_controller.switcherStyle) {
      case WallpaperGroupSwitcherStyle.chips:
        return _buildGroupChips(context);
      case WallpaperGroupSwitcherStyle.grid5:
        return _buildGroupGrid5(context);
      case WallpaperGroupSwitcherStyle.sections:
        return const SizedBox();
    }
  }

  Widget _buildGroupChips(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selecting = _selection.isSelecting;
        final viewedId = _controller.selectedGroupId;
        final selectedIds = _selectedGroupIds();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      // The stopped indicator sits on group 0: the wallpaper is
                      // either playing a group or not playing at all.
                      avatar: wallpaperEngineLink.isPlaying ? null : Icon(AIcons.wallpaperStopped, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      label: Text(l10n.wallpaperGroupNone),
                      // Group 0 is a view choice, never part of a delete selection.
                      selected: !selecting && viewedId == null,
                      onSelected: selecting ? null : (_) => unawaited(_controller.selectGroup(null)),
                      showCheckmark: false,
                    ),
                  ),
                  for (final group in _controller.groups)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: GestureDetector(
                        onLongPress: () => _onGroupCardLongPress(group.id),
                        child: Tooltip(
                          // The chips mode has no room for a subtitle, so the note
                          // reads as a tooltip instead.
                          message: group.description,
                          child: ChoiceChip(
                            avatar: selecting
                                ? Icon(selectedIds.contains(group.id) ? AIcons.selected : AIcons.unselected, size: 18)
                                : _groupStateIcon(context, group),
                            label: Text('${group.number}  ${wallpaperGroupName(context, group)}'),
                            selected: selecting ? selectedIds.contains(group.id) : viewedId == group.id,
                            labelStyle: group.enabled ? null : TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            showCheckmark: false,
                            onSelected: (_) => _onGroupCardTap(group.id),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
              child: WallpaperGroupAvailabilityLabel(gallerySuspended: _gallerySuspended),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupGrid5(BuildContext context) {
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selecting = _selection.isSelecting;
        final selectedIds = _selectedGroupIds();
        return LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            const padding = 12.0;
            final width = (constraints.maxWidth - padding * 2 - spacing * (_grid5ColumnCount - 1)) / _grid5ColumnCount;
            final height = width * 1.25;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final groupId in _groupFilters.keys)
                        SizedBox(
                          width: width,
                          height: height,
                          child: WallpaperGroupTile(
                            filter: _buildGroupFilter(groupId),
                            tileLayout: TileLayout.grid,
                            tileSize: Size(width, height),
                            selecting: selecting,
                            selected: selectedIds.contains(groupId),
                            onTap: () => _onGroupCardTap(groupId == wallpaperGroupNoneId ? null : groupId),
                            // Always provide a handler so a group card consumes the
                            // long press instead of the grid's range selection.
                            onLongPress: () => _onGroupCardLongPress(groupId == wallpaperGroupNoneId ? null : groupId),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: spacing),
                  WallpaperGroupAvailabilityLabel(gallerySuspended: _gallerySuspended),
                ],
              ),
            );
          },
        );
      },
    );
  }

  FilterGridItem<CollectionFilter> _groupItem(String groupId) => FilterGridItem<CollectionFilter>(_buildGroupFilter(groupId), null);

  /// A group card switches the viewed group, or joins the selection while the
  /// page is selecting. Group 0 is a view choice and is never selectable.
  void _onGroupCardTap(String? groupId) {
    if (_selection.isSelecting) {
      if (groupId != null) _selection.toggleSelection(_groupItem(groupId));
      return;
    }
    unawaited(_controller.selectGroup(groupId));
  }

  /// Long press starts multi-selection with this group, mirroring the condition
  /// tiles' selection mode.
  void _onGroupCardLongPress(String? groupId) {
    if (groupId == null) return;
    _selection.toggleSelection(_groupItem(groupId));
  }

  Widget? _groupStateIcon(BuildContext context, WallpaperGroup group) {
    final colors = Theme.of(context).colorScheme;
    // The play icon wins: the chip must say what is playing before what is
    // enabled, and both can be true.
    if (wallpaperEngineLink.isPlaying && group.current) {
      return Icon(AIcons.wallpaperPlaying, size: 18, color: colors.tertiary);
    }
    if (group.enabled) {
      return Tooltip(
        message: context.l10n.wallpaperGroupEnabled,
        child: Icon(AIcons.visibleRangeActive, size: 18, color: colors.primary),
      );
    }
    return null;
  }

  WallpaperGroupFilter _buildGroupFilter(String groupId) {
    final group = groupId == wallpaperGroupNoneId ? null : _controller.groups.firstWhereOrNull((candidate) => candidate.id == groupId);
    final filters = _groupFilters[groupId];
    return WallpaperGroupFilter(
      groupId: group?.id,
      number: group?.number ?? 0,
      name: group?.name ?? '@wallpaperGroupNone',
      description: group?.description ?? '',
      enabled: group?.enabled ?? true,
      playing: group != null && group.current && wallpaperEngineLink.isPlaying,
      stopped: group == null && !wallpaperEngineLink.isPlaying,
      selected: _controller.selectedGroupId == group?.id,
      count: filters == null ? null : _stats[filterFingerprint(filters)]?.count,
    );
  }

  // sections

  Map<ChipSectionKey, List<FilterGridItem<CollectionFilter>>> _buildSections(BuildContext context) {
    final result = <ChipSectionKey, List<FilterGridItem<CollectionFilter>>>{};
    if (_controller.switcherStyle == WallpaperGroupSwitcherStyle.sections) {
      result[WallpaperGroupSectionKey(context, gallerySuspended: _gallerySuspended)] = [
        for (final groupId in _groupFilters.keys) _groupItem(groupId),
      ];
    }
    final range = _controller.range;
    if (range == null) return result;
    final supplementsOutside = range.order.isIntersectFirst;
    for (final section in buildWallpaperGroupSections(range: range)) {
      final real = section.candidates.where((candidate) => !candidate.placeholder).toList();
      final countText = switch (section.kind) {
        // The base is exclusive: the section already says so, and the count of
        // the control tiles would only confuse it with conditions.
        VisibleRangeCandidateKind.base => '',
        VisibleRangeCandidateKind.restriction || VisibleRangeCandidateKind.supplement =>
          real.isEmpty ? '' : '${real.where((candidate) => candidate.active).length}/${real.length}',
      };
      final key = VisibleRangeSectionKey(context, section.kind, countText: countText, supplementsOutside: supplementsOutside);
      result[key] = [
        for (final candidate in section.candidates) FilterGridItem<CollectionFilter>(VisibleRangeCandidateFilter(candidate), null),
      ];
    }
    if (_controller.activeStyle == VisibleRangeActiveStyle.section) {
      final active = buildWallpaperGroupActiveCandidates(range: range);
      result[VisibleRangeActiveSectionKey(context, restricted: range.isRestricted)] = [
        for (final candidate in active) FilterGridItem<CollectionFilter>(VisibleRangeCandidateFilter(candidate, summary: true), null),
      ];
    }
    return result;
  }

  Widget _buildTile(BuildContext context, FilterGridItem<CollectionFilter> item, Size tileSize) {
    final filter = item.filter;
    if (filter is WallpaperGroupFilter) {
      return MetaData(
        metaData: ScalerMetadata(item),
        child: ListenableBuilder(
          listenable: _selection,
          builder: (context, _) => WallpaperGroupTile(
            filter: filter,
            tileLayout: settings.getTileLayout(GroupedWallpaperPage.routeName),
            tileSize: tileSize,
            selecting: _selection.isSelecting,
            selected: _selectedGroupIds().contains(filter.groupId),
            onTap: () => _onGroupCardTap(filter.groupId),
            // Always provide a handler so the shared grid selector does not treat
            // group 0 (never selectable) as a selectable item on long press.
            onLongPress: () => _onGroupCardLongPress(filter.groupId),
          ),
        ),
      );
    }
    final candidateFilter = filter as VisibleRangeCandidateFilter;
    final candidate = candidateFilter.candidate;
    return MetaData(
      metaData: ScalerMetadata(item),
      child: ListenableBuilder(
        listenable: _selection,
        builder: (context, _) => VisibleRangeTile(
          gridItem: FilterGridItem(candidateFilter, item.entry),
          // Controls are not conditions: an empty-section slot shares the empty
          // filter set with 「Unrestricted」, so it must not inherit its cover and
          // count.
          stats: candidate.placeholder ? null : (candidate.isGallery ? _resultStats : _stats[candidate.statsKey]),
          tileLayout: settings.getTileLayout(GroupedWallpaperPage.routeName),
          tileSize: tileSize,
          summary: candidateFilter.summary,
          // The result preview and the empty-section slots carry no state; the
          // base and rule tiles do, including 「Unrestricted」.
          showStateIcon: !candidate.isGallery && !candidate.placeholder,
          selectable: !candidateFilter.summary && _isSelectable(candidate),
          selecting: _selection.isSelecting,
          selected: _selection.selectedItems.contains(item),
          labelOverride: _labelOverride(context, candidate),
          onTap: () => _onTileTap(item),
        ),
      ),
    );
  }

  /// The group page selects only real conditions: the group's own base and its
  /// rules. Placeholders and the result preview are controls, not data.
  bool _isSelectable(VisibleRangeCandidate candidate) => candidate.rule != null || isWallpaperGroupBaseCandidate(candidate);

  /// Cover chips have no room for long text, so the empty-section slots use the
  /// short label in every layout.
  String _labelOverride(BuildContext context, VisibleRangeCandidate candidate) {
    if (!candidate.placeholder) return '';
    return context.l10n.wallpaperGroupSectionNone;
  }

  Widget _buildFooter(BuildContext context) {
    final range = _controller.range;
    if (range == null) return const SizedBox();
    final baseCandidates = buildWallpaperGroupSections(range: range).first.candidates;
    final activeBase = baseCandidates.firstWhereOrNull((candidate) => candidate.active && !candidate.placeholder);
    final activeRules = [
      for (final kind in range.order.isIntersectFirst
          ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement]
          : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
        for (final rule in range.activeRulesOf(kind)) VisibleRangeCandidate.fromRule(rule),
    ];
    return VisibleRangeActiveFooter(
      range: range,
      activeBase: activeBase,
      activeRules: activeRules,
      style: _controller.activeStyle,
      resultStats: _resultStats,
      statsFor: (candidate) => _stats[candidate.statsKey],
      tileExtent: context.select<TileExtentController, double>((controller) => controller.extentNotifier.value),
      onCancelBase: _cancelBase,
      onCancelRule: (candidate) {
        final rule = candidate.rule;
        if (rule != null) _toggleRule(rule);
      },
      onAbout: _openAbout,
    );
  }

  void _toggleRule(VisibleRangeRule rule) {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    unawaited(_controller.toggleRule(rule.id));
  }

  void _cancelBase() {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    // Cancelling the base switches it off without losing it, so the user can
    // put it back.
    unawaited(_controller.setBaseActive(false));
  }

  Future<void> _openAbout() => Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: VisibleRangeAboutPage.routeName),
          builder: (_) => const VisibleRangeAboutPage(wallpaperFirst: true),
        ),
      );

  void _onTileTap(FilterGridItem<CollectionFilter> item) {
    final filter = item.filter;
    if (filter is WallpaperGroupFilter) {
      _onGroupCardTap(filter.groupId);
      return;
    }
    final candidateFilter = filter as VisibleRangeCandidateFilter;
    final candidate = candidateFilter.candidate;
    if (_controller.selectedGroupId == null) return;
    if (_selection.isSelecting) {
      if (_isSelectable(candidate)) _selection.toggleSelection(item);
      return;
    }
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    if (candidateFilter.summary) {
      final rule = candidate.rule;
      if (rule != null) {
        unawaited(_controller.toggleRule(rule.id));
      } else if (!candidate.isGallery && isWallpaperGroupBaseCandidate(candidate)) {
        unawaited(_controller.setBaseActive(false));
      }
      return;
    }
    // Placeholders are controls, not conditions: an empty section slot does
    // nothing.
    if (candidate.placeholder) return;
    switch (candidate.kind) {
      case VisibleRangeCandidateKind.base:
        if (candidate.isUnrestricted) {
          // 「All images」 switches the group's base off instead of deleting its
          // conditions, so they stay available on the base tile. Rules are a
          // separate section and keep their own switches, like on the gallery
          // page. Nothing is written when the base already narrows nothing.
          if (!(_controller.range?.isBaseUnrestricted ?? true)) unawaited(_controller.setBaseActive(false));
        } else if (isWallpaperGroupBaseCandidate(candidate)) {
          unawaited(_controller.toggleBaseActive());
        }
      case VisibleRangeCandidateKind.restriction:
      case VisibleRangeCandidateKind.supplement:
        final rule = candidate.rule;
        if (rule != null) unawaited(_controller.toggleRule(rule.id));
    }
  }

  // view preferences

  Widget _buildActiveStyleRow(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AIcons.visibleRangeActive),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.visibleRangeActiveStyle)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<VisibleRangeActiveStyle>(
              segments: [
                ButtonSegment(value: VisibleRangeActiveStyle.section, label: Text(l10n.visibleRangeActiveStyleSection)),
                ButtonSegment(value: VisibleRangeActiveStyle.compactChips, label: Text(l10n.visibleRangeActiveStyleChips)),
                ButtonSegment(value: VisibleRangeActiveStyle.tiles, label: Text(l10n.visibleRangeActiveStyleTiles)),
              ],
              selected: {_controller.activeStyle},
              onSelectionChanged: (selection) => unawaited(_controller.setActiveStyle(selection.first)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitcherStyleRow(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AIcons.wallpaper),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.wallpaperGroupSwitcherStyle)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<WallpaperGroupSwitcherStyle>(
              segments: [
                ButtonSegment(value: WallpaperGroupSwitcherStyle.chips, label: Text(l10n.wallpaperGroupSwitcherChips)),
                ButtonSegment(value: WallpaperGroupSwitcherStyle.sections, label: Text(l10n.wallpaperGroupSwitcherSections)),
                ButtonSegment(value: WallpaperGroupSwitcherStyle.grid5, label: Text(l10n.wallpaperGroupSwitcherGrid5)),
              ],
              selected: {_controller.switcherStyle},
              onSelectionChanged: (selection) => unawaited(_controller.setSwitcherStyle(selection.first)),
            ),
          ],
        ),
      ),
    );
  }

  // app bar

  /// The TV rail has no overflow menu, so the selection actions stay reachable
  /// as icons, mirroring the visible-range page.
  List<Widget> _buildExtraActions(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<CollectionFilter>> selection,
    WallpaperGroupActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      if (!settings.useTvLayout) return const [];
      final candidates = _selectedCandidates(selection);
      final rules = _selectedRules(selection);
      final hasBase = _selectionHasBase(selection);
      final groups = _selectedGroupIds(selection);
      return [
        if (candidates.any((candidate) => candidate.isApplicable))
          IconButton(
            icon: const Icon(AIcons.apply),
            tooltip: context.l10n.visibleRangeApplyToMediaSet,
            onPressed: () => unawaited(_applySelectionToMediaSet()),
          ),
        if (rules.length == 1 && candidates.length == 1 && !hasBase)
          IconButton(
            icon: const Icon(AIcons.edit),
            tooltip: context.l10n.visibleRangeEditRule,
            onPressed: () => unawaited(_editRule(rules.first)),
          ),
        if (rules.length == 1 && candidates.length == 1 && !hasBase)
          IconButton(
            icon: const Icon(AIcons.rename),
            tooltip: context.l10n.visibleRangeActionRename,
            onPressed: () => unawaited(_renameRule(rules.first)),
          ),
        if (rules.isNotEmpty || hasBase)
          IconButton(
            icon: const Icon(AIcons.delete),
            tooltip: context.l10n.visibleRangeActionDelete,
            onPressed: () => unawaited(_deleteSelectedConditions()),
          ),
        if (groups.isNotEmpty)
          IconButton(
            icon: const Icon(AIcons.delete),
            tooltip: context.l10n.wallpaperGroupDeleteSelected,
            onPressed: () => unawaited(_deleteSelectedGroups()),
          ),
      ];
    }
    if (!settings.useTvLayout) return const [];
    return [
      PopupMenuButton<_PageAction>(
        icon: const Icon(AIcons.more),
        tooltip: context.l10n.visibleRangeMore,
        onSelected: (action) => unawaited(_onMenuSelected(action)),
        itemBuilder: _menuEntries,
      ),
    ];
  }

  /// Feature entries injected into the app bar's single overflow menu.
  List<PopupMenuEntry<Object>> _buildExtraMenuEntries(
    BuildContext context,
    AppMode appMode,
    Selection<FilterGridItem<CollectionFilter>> selection,
    WallpaperGroupActionDelegate delegate,
  ) {
    if (selection.isSelecting) {
      final candidates = _selectedCandidates(selection);
      final rules = _selectedRules(selection);
      final hasBase = _selectionHasBase(selection);
      final groups = _selectedGroupIds(selection);
      return [
        if (candidates.any((candidate) => candidate.isApplicable)) _menuItem(_PageAction.applyToMediaSet, AIcons.apply, context.l10n.visibleRangeApplyToMediaSet),
        if (rules.length == 1 && candidates.length == 1 && !hasBase) _menuItem(_PageAction.editRule, AIcons.edit, context.l10n.visibleRangeEditRule),
        if (rules.length == 1 && candidates.length == 1 && !hasBase) _menuItem(_PageAction.renameRule, AIcons.rename, context.l10n.visibleRangeActionRename),
        if (rules.isNotEmpty || hasBase) _menuItem(_PageAction.deleteSelectedConditions, AIcons.delete, context.l10n.visibleRangeActionDelete),
        if (groups.isNotEmpty) _menuItem(_PageAction.deleteSelectedGroups, AIcons.delete, context.l10n.wallpaperGroupDeleteSelected),
      ];
    }
    return _menuEntries(context);
  }

  List<VisibleRangeCandidate> _selectedCandidates(Selection<FilterGridItem<CollectionFilter>> selection) {
    if (!selection.isSelecting) return const [];
    return [
      for (final item in selection.selectedItems)
        if (item.filter is VisibleRangeCandidateFilter) (item.filter as VisibleRangeCandidateFilter).candidate,
    ];
  }

  Set<VisibleRangeRule> _selectedRules(Selection<FilterGridItem<CollectionFilter>> selection) {
    if (!selection.isSelecting) return {};
    return _selectedCandidates(selection).map((candidate) => candidate.rule).nonNulls.toSet();
  }

  bool _selectionHasBase(Selection<FilterGridItem<CollectionFilter>> selection) {
    if (!selection.isSelecting) return false;
    return _selectedCandidates(selection).any(isWallpaperGroupBaseCandidate);
  }

  /// Ids of the selected group cards, restricted to groups that still exist.
  /// Group 0 has no id and is never selectable.
  Set<String> _selectedGroupIds([Selection<FilterGridItem<CollectionFilter>>? selection]) {
    final current = selection ?? _selection;
    if (!current.isSelecting) return {};
    return {
      for (final group in _controller.groups)
        if (current.isSelected([_groupItem(group.id)])) group.id,
    };
  }

  /// Takes the selected candidates out to the media set, exactly like the
  /// visible-range page: the union of their filters is appended and every
  /// target is remembered for the pin sheet's write-back list.
  Future<void> _applySelectionToMediaSet() async {
    final range = _controller.range;
    if (!_selection.isSelecting || range == null) return;
    final candidates = _selectedCandidates(_selection);
    if (candidates.isEmpty) return;
    _selection.browse();
    await applyVisibleRangeCandidates(context, rangeId: range.id, candidates: candidates);
  }

  Future<void> _deleteSelectedConditions() async {
    final rules = _selectedRules(_selection);
    final base = _selectionHasBase(_selection);
    if (rules.isEmpty && !base) return;
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    _selection.browse();
    await _controller.deleteConditions(base: base, ruleIds: rules.map((rule) => rule.id).toSet());
  }

  /// Deletes the selected group cards. The group controller keeps at least one
  /// group, so a selection that would empty the list is refused as a whole.
  Future<void> _deleteSelectedGroups() async {
    final ids = _selectedGroupIds();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.wallpaperGroupDeleteSelectedConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    _selection.browse();
    final deleted = await _controller.deleteGroups(ids);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperGroupKeepOne)));
      return;
    }
    // Deleting the group that was playing turns the feature off and freezes the
    // frame, so the engine has to re-read the saved state.
    await _prepareWallpaper();
  }

  /// Renames one rule and edits its note. Filters are never edited here: a
  /// condition comes from a media set through 「pin to visible range」.
  Future<void> _renameRule(VisibleRangeRule rule) async {
    if (!_controller.canEdit) {
      _showBlocked();
      return;
    }
    final result = await _askGroupTexts(
      title: context.l10n.visibleRangeActionRename,
      initialName: rule.label,
      initialDescription: rule.description,
    );
    if (result == null) return;
    await _controller.renameRule(rule.id, label: result.name, description: result.description);
    // The renamed rule is a new value, so the selection cannot keep pointing at
    // the old one.
    _selection.browse();
  }

  /// Opens the shared rule actions and applies the chosen one to this group.
  ///
  /// The sheet is the same one the visible-range page uses; only the write path
  /// differs, because a wallpaper group keeps its edits in the page's draft.
  Future<void> _editRule(VisibleRangeRule rule) async {
    if (_controller.range == null) return;
    final action = await showVisibleRangeRuleActions(context, rule: rule, canEdit: _controller.canEdit);
    if (action == null || !mounted) return;
    switch (action) {
      case VisibleRangeRuleAction.rename:
        await _renameRule(rule);
      case VisibleRangeRuleAction.moveToBase:
        if (!_controller.canEdit) {
          _showBlocked();
          return;
        }
        _selection.browse();
        await _controller.moveRuleToBase(rule.id, name: visibleRangeRuleLabel(context, rule));
      case VisibleRangeRuleAction.moveToRestriction:
      case VisibleRangeRuleAction.moveToSupplement:
        if (!_controller.canEdit) {
          _showBlocked();
          return;
        }
        _selection.browse();
        await _controller.moveRuleToKind(
          rule.id,
          action == VisibleRangeRuleAction.moveToRestriction ? VisibleRangeRuleKind.restriction : VisibleRangeRuleKind.supplement,
        );
      case VisibleRangeRuleAction.activateReplace:
        await _activateRule(rule, replace: true);
      case VisibleRangeRuleAction.activateAppend:
        await _activateRule(rule, replace: false);
      case VisibleRangeRuleAction.delete:
        if (!_controller.canEdit) {
          _showBlocked();
          return;
        }
        _selection.browse();
        await _controller.deleteConditions(ruleIds: {rule.id});
    }
  }

  /// Opens the media set with the rule's conditions, replacing what it shows or
  /// appending to it. Nothing is written: the user keeps working there.
  Future<void> _activateRule(VisibleRangeRule rule, {required bool replace}) async {
    final current = mediaSetTab.currentFilters ?? const <CollectionFilter>{};
    final target = replace ? rule.filters : {...current, ...rule.filters};
    _selection.browse();
    await AvesNavItem(route: CollectionPage.routeName, filters: target).goTo(context, topLevel: false);
  }

  /// Locks the group's range with per-permission control.
  ///
  /// The group page has no "last preset" of its own, so the dialog opens on the
  /// most restrictive one; the user can still pick another or toggle each
  /// permission.
  Future<void> _lockDetailed() async {
    final permissions = await showDialog<VisibleRangePermissions>(
      context: context,
      builder: (context) => const VisibleRangeLockDialog(initialPreset: VisibleRangeLockPreset.readOnly),
    );
    if (permissions == null) return;
    await _controller.lock(permissions: permissions);
  }

  List<PopupMenuEntry<_PageAction>> _menuEntries(BuildContext context) {
    final l10n = context.l10n;
    final group = _selectedGroup;
    final range = _controller.range;
    final locked = range?.locked ?? false;
    final canDelete = _controller.groups.length > 1;
    final gallery = visibleRangeController.gallery;
    final canSuspendGallery = gallery.isRestricted && !gallery.locked;
    final engineActive = wallpaperEngineLink.isActive;
    return [
      // Draft actions come first: nothing below reaches the database until the
      // user saves, so the state and its two follow-ups stay together.
      _menuItem(
        _PageAction.saveChanges,
        AIcons.save,
        l10n.wallpaperGroupSaveChanges,
        enabled: _controller.dirty,
        subtitle: _controller.dirty ? l10n.wallpaperGroupDraftUnsaved : null,
      ),
      // One action, following the group the page is viewing: a real group
      // becomes the wallpaper, group 0 turns the feature off. The system picker
      // is only needed the first time, when the service is not the wallpaper yet.
      if (group == null)
        _menuItem(
          _PageAction.disableWallpaper,
          AIcons.wallpaperStopped,
          l10n.wallpaperGroupDisableWallpaper,
          enabled: wallpaperEngineLink.isAttached && !wallpaperEngineLink.isDisabled,
          subtitle: wallpaperEngineLink.isAttached && wallpaperEngineLink.isDisabled ? l10n.wallpaperGroupAlreadyDisabled : null,
        )
      else
        _menuItem(
          _PageAction.setCurrentAsWallpaper,
          AIcons.wallpaperPlaying,
          l10n.wallpaperGroupSetCurrentAsWallpaper,
          enabled: wallpaperEngineLink.isAttached && group.enabled,
          subtitle: wallpaperEngineLink.isAttached
              ? (group.current && wallpaperEngineLink.isPlaying ? l10n.wallpaperGroupAlreadyPlaying : null)
              : l10n.wallpaperGroupEngineUnavailable,
        ),
      _menuItem(
        _PageAction.syncNow,
        AIcons.sync,
        l10n.wallpaperGroupSyncNow,
        enabled: engineActive && !wallpaperEngineLink.isDisabled,
        subtitle: engineActive ? null : l10n.wallpaperGroupSyncInactive,
      ),
      _menuItem(
        _PageAction.engineStatus,
        AIcons.wallpaper,
        l10n.wallpaperGroupEngineStatus,
        enabled: false,
        subtitle: _engineStatusText(context),
      ),
      _menuItem(
        _PageAction.viewCurrent,
        AIcons.wallpaperPlaying,
        l10n.wallpaperGroupViewCurrent,
        enabled: engineActive && !wallpaperEngineLink.isDisabled,
        subtitle: engineActive && !wallpaperEngineLink.isDisabled ? null : l10n.wallpaperGroupSyncInactive,
      ),
      _menuItem(
        _PageAction.effects,
        AIcons.palette,
        l10n.muzeiWallpaperEffects,
        enabled: group != null,
      ),
      _menuItem(
        _PageAction.autoAdvance,
        AIcons.autoAdvance,
        l10n.muzeiWallpaperAutoAdvance,
        enabled: group != null,
        subtitle: group == null ? null : groupedWallpaperAutoAdvanceSummary(context, group),
      ),
      _menuItem(_PageAction.gestures, AIcons.gestures, l10n.wallpaperGroupGestures),
      _menuItem(_PageAction.history, AIcons.history, l10n.wallpaperGroupHistoryTitle),
      _menuItem(_PageAction.historyLimit, AIcons.count, l10n.wallpaperGroupHistoryLimit),
      _menuItemChecked(
        _PageAction.toggleScrollEffect,
        l10n.wallpaperUseScrollEffect,
        checked: wallpaperEngineLink.scrollEffectEnabled,
      ),
      _menuItemChecked(
        _PageAction.toggleNotification,
        l10n.wallpaperGroupNotification,
        checked: wallpaperEngineLink.notificationEnabled,
      ),
      _menuItem(
        _PageAction.discardChanges,
        AIcons.discard,
        l10n.wallpaperGroupDiscardChanges,
        enabled: _controller.dirty,
      ),
      const PopupMenuDivider(),
      // The wallpaper page shares one bottom-bar entry with the visible-range
      // page in the shared mode; this switches that destination for the rest of
      // the process. With a separate entry the page is already on the bar, so
      // the same place closes or reopens the derived entry instead. An entry the
      // user added themselves is theirs: the menu never touches it.
      if (groupedWallpaperNavController.mode == GroupedWallpaperNavMode.shared)
        _menuItem(_PageAction.visibleRange, AIcons.visibleRange, l10n.visibleRangePageTitle)
      else if (!_wallpaperEntryPinned)
        _menuItem(
          _PageAction.toggleNavEntry,
          AIcons.wallpaper,
          groupedWallpaperNavController.entryClosed ? l10n.wallpaperGroupNavOpen : l10n.wallpaperGroupNavClose,
        ),
      if (gallery.isRestricted)
        _menuItem(
          _PageAction.cancelGalleryRange,
          gallery.locked ? AIcons.locked : AIcons.visibleRangeActive,
          _gallerySuspended ? l10n.wallpaperGroupRestoreGalleryRange : l10n.wallpaperGroupCancelGalleryRange,
          enabled: canSuspendGallery,
          subtitle: gallery.locked ? l10n.visibleRangeWhenLocked : null,
        ),
      const PopupMenuDivider(),
      if (group != null) ...[
        _menuItem(
          _PageAction.toggleEnabled,
          group.enabled ? AIcons.unselected : AIcons.checked,
          group.enabled ? l10n.wallpaperGroupDisable : l10n.wallpaperGroupEnable,
        ),
        _menuItem(_PageAction.moveUp, AIcons.up, l10n.wallpaperGroupMoveUp),
        _menuItem(_PageAction.moveDown, AIcons.down, l10n.wallpaperGroupMoveDown),
        const PopupMenuDivider(),
        _menuItem(_PageAction.rename, AIcons.edit, l10n.wallpaperGroupRename),
        _menuItem(
          _PageAction.duplicateGroup,
          AIcons.copy,
          l10n.wallpaperGroupDuplicate,
          enabled: !locked,
          subtitle: locked ? l10n.visibleRangeManagementBlocked : null,
        ),
      ],
      _menuItem(_PageAction.add, AIcons.add, l10n.wallpaperGroupAdd),
      if (group != null) _menuItem(_PageAction.delete, AIcons.delete, l10n.wallpaperGroupDelete, enabled: canDelete),
      const PopupMenuDivider(),
      if (range != null) ...[
        _menuItem(_PageAction.order, AIcons.sortOrder, l10n.visibleRangeOrder),
        _menuItem(_PageAction.lock, locked ? AIcons.locked : AIcons.unlocked, locked ? l10n.visibleRangeUnlock : l10n.visibleRangeLock),
        _menuItem(_PageAction.lockDetailed, AIcons.locked, l10n.visibleRangeLockSheetTitle),
        const PopupMenuDivider(),
      ],
      _menuItem(_PageAction.about, AIcons.info, l10n.aboutWallpaperTitle),
    ];
  }

  PopupMenuItem<_PageAction> _menuItem(_PageAction value, IconData icon, String text, {bool enabled = true, String? subtitle}) => PopupMenuItem<_PageAction>(
        value: value,
        enabled: enabled,
        child: _menuRow(icon, text, subtitle: subtitle),
      );

  /// A menu entry whose checkmark is the setting's state, not an action icon.
  PopupMenuItem<_PageAction> _menuItemChecked(_PageAction value, String text, {required bool checked}) => CheckedPopupMenuItem<_PageAction>(
        value: value,
        checked: checked,
        child: _menuRow(null, text),
      );

  Widget _menuRow(IconData? icon, String text, {String? subtitle}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text),
              if (subtitle != null) Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  WallpaperGroup? get _selectedGroup {
    final id = _controller.selectedGroupId;
    if (id == null) return null;
    return _controller.groups.firstWhereOrNull((group) => group.id == id);
  }

  /// Whether the user put the wallpaper group page in their own navigation list.
  ///
  /// Such an entry is theirs to keep or remove from the navigation editor, so
  /// the page menu must not offer to close it.
  bool get _wallpaperEntryPinned => settings.bottomNavigationActions.any((item) => item.route == GroupedWallpaperPage.routeName);

  Future<void> _onMenuSelected(_PageAction action) async {
    final group = _selectedGroup;
    switch (action) {
      case _PageAction.visibleRange:
        visibleRangeDestination.value = VisibleRangeDestination.range;
      case _PageAction.toggleNavEntry:
        await _toggleNavEntry();
      case _PageAction.saveChanges:
        await _saveDraft();
      case _PageAction.discardChanges:
        await _discardDraft();
      case _PageAction.syncNow:
        await _syncNow();
      case _PageAction.setCurrentAsWallpaper:
        if (group != null) await _setCurrentAsWallpaper(group);
      case _PageAction.disableWallpaper:
        await _disableWallpaper();
      case _PageAction.viewCurrent:
        await _viewCurrent();
      case _PageAction.effects:
        if (group != null) await _openEffects(group);
      case _PageAction.autoAdvance:
        if (group != null) await _openAutoAdvance(group);
      case _PageAction.gestures:
        await _openGestures();
      case _PageAction.history:
        await _openHistory();
      case _PageAction.historyLimit:
        await _editHistoryLimit();
      case _PageAction.duplicateGroup:
        if (group != null) await _duplicateGroup(group);
      case _PageAction.toggleNotification:
        await _toggleNotification();
      case _PageAction.toggleScrollEffect:
        await _toggleScrollEffect();
      case _PageAction.engineStatus:
        break;
      case _PageAction.cancelGalleryRange:
        _toggleGallerySuspension();
      case _PageAction.toggleEnabled:
        if (group != null) {
          await _controller.setEnabled(group.id, !group.enabled);
          await _prepareWallpaper();
        }
      case _PageAction.moveUp:
        if (group != null) await _controller.moveGroup(group.id, -1);
      case _PageAction.moveDown:
        if (group != null) await _controller.moveGroup(group.id, 1);
      case _PageAction.rename:
        if (group != null) await _renameGroup(group);
      case _PageAction.add:
        await _addGroup();
      case _PageAction.delete:
        if (group != null) await _deleteGroup(group);
      case _PageAction.order:
        await _pickOrder();
      case _PageAction.lock:
        await _toggleLock();
      case _PageAction.lockDetailed:
        await _lockDetailed();
      case _PageAction.about:
        await _openAbout();
      case _PageAction.applyToMediaSet:
        await _applySelectionToMediaSet();
      case _PageAction.editRule:
        final rules = _selectedRules(_selection);
        if (rules.length == 1) await _editRule(rules.first);
      case _PageAction.renameRule:
        final rules = _selectedRules(_selection);
        if (rules.length == 1) await _renameRule(rules.first);
      case _PageAction.deleteSelectedConditions:
        await _deleteSelectedConditions();
      case _PageAction.deleteSelectedGroups:
        await _deleteSelectedGroups();
    }
  }

  Future<void> _saveDraft() async {
    await _controller.saveDraft();
    // Saving is what the wallpaper follows: re-bake now so the frame on screen
    // matches what the user just saved instead of waiting for a manual sync.
    await _prepareWallpaper();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperGroupSaved)));
  }

  Future<void> _discardDraft() async {
    if (!_controller.dirty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.wallpaperGroupDiscardConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.discardDraft();
    await _prepareWallpaper();
  }

  /// Makes [group] the wallpaper's group and turns the feature on.
  ///
  /// The system chooser is only needed the first time: once the grouped service
  /// is the system wallpaper, this just switches content. The frame is prepared
  /// before the chooser opens, so the picker shows a photo instead of the
  /// placeholder while the system commits the change.
  Future<void> _setCurrentAsWallpaper(WallpaperGroup group) async {
    // The notification is the only way to control the wallpaper from the lock
    // screen, so ask for the permission at the moment it first becomes useful.
    try {
      await Permission.notification.request();
    } catch (error, stack) {
      groupedWallpaperLog.w('failed to request the notification permission', error, stack);
    }
    await _controller.selectCurrent(group.id);
    if (_controller.dirty) await _controller.saveDraft();
    await wallpaperEngineLink.setDisabled(false);
    await wallpaperEngineLink.prepare();
    await _refreshEngine();
    if (!mounted) return;
    if (!wallpaperEngineLink.isActive) {
      await _setWallpaper();
      return;
    }
    _showMessage(context.l10n.wallpaperGroupWallpaperSet(wallpaperGroupName(context, group)));
  }

  /// Turns the grouped wallpaper off without touching what is on screen.
  ///
  /// The last frame stays: disabling stops following the group, it does not
  /// change the wallpaper the system is already showing.
  Future<void> _disableWallpaper() async {
    await wallpaperEngineLink.setDisabled(true);
    await wallpaperEngineLink.prepare();
    await _refreshEngine();
    if (!mounted) return;
    _showMessage(context.l10n.wallpaperGroupWallpaperDisabled);
  }

  /// Saves a pending draft first, then asks the running engine to apply it now
  /// instead of waiting for the wallpaper's interval.
  Future<void> _syncNow() async {
    await _refreshEngine();
    if (!mounted) return;
    if (!wallpaperEngineLink.isActive) {
      _showMessage(context.l10n.wallpaperGroupSyncInactive);
      return;
    }
    if (wallpaperEngineLink.isDisabled) {
      _showMessage(context.l10n.wallpaperGroupSyncDisabled);
      return;
    }
    if (_controller.dirty) await _controller.saveDraft();
    final result = await wallpaperEngineLink.syncNow();
    await _refreshEngine();
    if (!mounted) return;
    _showMessage(
      switch (result) {
        GroupedWallpaperSyncResult.baked => context.l10n.wallpaperGroupSyncDone,
        GroupedWallpaperSyncResult.empty => context.l10n.wallpaperGroupSyncEmpty,
        GroupedWallpaperSyncResult.locked => context.l10n.wallpaperGroupSyncLocked,
        GroupedWallpaperSyncResult.disabled => context.l10n.wallpaperGroupSyncDisabled,
        GroupedWallpaperSyncResult.unchanged => context.l10n.wallpaperGroupSyncDone,
        GroupedWallpaperSyncResult.notActive => context.l10n.wallpaperGroupSyncInactive,
        GroupedWallpaperSyncResult.failed => context.l10n.wallpaperGroupSyncFailed,
      },
    );
  }

  /// Opens the system live-wallpaper chooser for the grouped service.
  ///
  /// The picker takes over the screen, so the engine state is re-read on resume
  /// rather than here; this only reports an OEM that has no picker at all.
  Future<void> _setWallpaper() async {
    final opened = await wallpaperEngineLink.openChooser();
    if (!mounted || opened) return;
    _showMessage(context.l10n.wallpaperGroupChooserUnavailable);
  }

  /// Opens the immersive view of the photo the wallpaper is showing.
  Future<void> _viewCurrent() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperViewPage.routeName),
        builder: (_) => const GroupedWallpaperViewPage(groupPageBelow: true),
      ),
    );
  }

  /// Opens the effects editor for [group], bound to that group's own values.
  Future<void> _openEffects(WallpaperGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperEffectsPage.routeName),
        builder: (_) => GroupedWallpaperEffectsPage(
          groupId: group.id,
          controller: _controller,
        ),
      ),
    );
    // The page may have re-baked the frame, so the status row can have changed.
    await _refreshEngine();
  }

  /// Opens the auto-advance editor for [group], bound to that group's own values.
  Future<void> _openAutoAdvance(WallpaperGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperAutoAdvancePage.routeName),
        builder: (_) => GroupedWallpaperAutoAdvancePage(
          groupId: group.id,
          controller: _controller,
        ),
      ),
    );
    // The schedule changed, so the engine status row can have changed too.
    await _refreshEngine();
  }

  /// Opens the global gesture bindings.
  Future<void> _openGestures() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperGesturesPage.routeName),
        builder: (_) => const GroupedWallpaperGesturesPage(),
      ),
    );
    // A binding change re-bakes the state, so the status row may have changed.
    await _refreshEngine();
  }

  /// Opens the photos the wallpaper has shown, newest first.
  ///
  /// It opens scoped to the group being viewed: the history belongs to a group,
  /// and reading another group's photos is what the lock is there to prevent.
  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: GroupedWallpaperHistoryPage.routeName),
        builder: (_) => GroupedWallpaperHistoryPage(groupId: _controller.selectedGroupId),
      ),
    );
  }

  /// Changes how many photos the usage history keeps.
  ///
  /// The store is the source of truth; the engine call only carries the value
  /// into `state.json`, so the notification greys "previous" without waiting for
  /// the next photo.
  Future<void> _editHistoryLimit() async {
    final store = WallpaperGroupStore(await getIt<AppDatabaseProvider>().open());
    final limit = await store.readHistoryLimit();
    if (!mounted) return;
    final value = await showGroupedWallpaperHistoryLimitDialog(context, limit: limit);
    if (value == null) return;
    await store.writeHistoryLimit(value);
    await wallpaperEngineLink.setHistoryLimit(value);
  }

  /// Copies [group] into a new group and opens the copy.
  ///
  /// A locked group is refused here and again in the controller: its range is
  /// read-only, so a copy would clone content the user froze.
  Future<void> _duplicateGroup(WallpaperGroup group) async {
    if (!_controller.canEdit) {
      _showMessage(context.l10n.visibleRangeManagementBlocked);
      return;
    }
    final name = context.l10n.wallpaperGroupCopyName(wallpaperGroupName(context, group));
    // The controller switches the page to the copy, and a draft stays a draft:
    // the unsaved banner is what tells the user that saving writes it.
    final copy = await _controller.duplicateGroup(group.id, name: name);
    if (!mounted) return;
    if (copy == null) _showMessage(context.l10n.visibleRangeManagementBlocked);
  }

  /// One line describing what the live wallpaper is doing, for the menu.
  String _engineStatusText(BuildContext context) {
    final l10n = context.l10n;
    if (!wallpaperEngineLink.isAttached) return l10n.wallpaperGroupEngineUnavailable;
    if (!wallpaperEngineLink.isActive) return l10n.wallpaperGroupSyncInactive;
    final state = _engineState;
    if (wallpaperEngineLink.isDisabled) {
      return state == null || state.groupId.isEmpty
          ? l10n.wallpaperGroupEngineDisabled
          : l10n.wallpaperGroupEngineDisabledGroup(state.groupNumber, state.groupName);
    }
    if (state == null) return l10n.wallpaperGroupEngineNeverSynced;
    return switch (state.status) {
      GroupedWallpaperStatus.ready =>
        state.entryTitle.isEmpty
            ? l10n.visibleRangeOwnerWithNumber(state.groupNumber, state.groupName)
            : l10n.wallpaperGroupEngineShowing(state.groupNumber, state.groupName, state.entryTitle),
      GroupedWallpaperStatus.locked => l10n.wallpaperGroupEngineLocked(state.groupNumber, state.groupName),
      GroupedWallpaperStatus.disabled => l10n.wallpaperGroupEngineDisabledGroup(state.groupNumber, state.groupName),
      GroupedWallpaperStatus.emptyGroup => l10n.wallpaperGroupEngineEmpty(state.groupName),
      GroupedWallpaperStatus.unavailable => l10n.wallpaperGroupEngineFailed,
    };
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Temporarily stops applying the gallery range to browsing on this page.
  ///
  /// It is a view choice only: nothing is written, and [dispose] restores it.
  void _toggleGallerySuspension() {
    setState(() => _gallerySuspended = !_gallerySuspended);
    _syncBrowsingOverlay();
  }

  Future<void> _renameGroup(WallpaperGroup group) async {
    final displayedName = wallpaperGroupName(context, group);
    final result = await _askGroupTexts(
      title: context.l10n.wallpaperGroupNameTitle,
      initialName: displayedName,
      initialDescription: group.description,
    );
    if (result == null) return;
    // Confirming without editing keeps a bundled (or unnamed) group's stored
    // value, so the name still follows the app language.
    final name = group.hasBundledName && result.name == displayedName ? group.name : result.name;
    await _controller.updateGroup(group.id, name: name, description: result.description);
  }

  Future<void> _addGroup() async {
    final result = await _askGroupTexts(
      title: context.l10n.wallpaperGroupAdd,
      initialName: '',
      // A new group's note defaults to the moment it was created, which is what
      // the card subtitle shows until the user writes something else.
      initialDescription: formatDateTime(DateTime.now(), settings.avesLocale, MediaQuery.alwaysUse24HourFormatOf(context)),
    );
    // An empty name is allowed: the group keeps its derived number until the
    // user names it.
    if (result == null) return;
    await _controller.addGroup(name: result.name, description: result.description);
  }

  Future<({String name, String description})?> _askGroupTexts({
    required String title,
    required String initialName,
    required String initialDescription,
  }) async {
    final l10n = context.l10n;
    final nameController = TextEditingController(text: initialName);
    final descriptionController = TextEditingController(text: initialDescription);
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.visibleRangePinName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.visibleRangePinDescription),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(
            onPressed: () => Navigator.pop(context, (name: nameController.text.trim(), description: descriptionController.text.trim())),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    return result;
  }

  Future<void> _deleteGroup(WallpaperGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.wallpaperGroupDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await _controller.deleteGroup(group.id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperGroupKeepOne)));
      return;
    }
    // Deleting the group that was playing turns the feature off and freezes the
    // frame, so the engine has to re-read the saved state.
    await _prepareWallpaper();
  }

  Future<void> _pickOrder() async {
    final l10n = context.l10n;
    final current = _controller.range?.order;
    final order = await showDialog<VisibleRangeOrder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.visibleRangeOrder),
        children: [
          _orderTile(context, title: l10n.visibleRangeOrderIntersectFirst, value: VisibleRangeOrder.intersectFirst, current: current),
          _orderTile(context, title: l10n.visibleRangeOrderUnionFirst, value: VisibleRangeOrder.unionFirst, current: current),
        ],
      ),
    );
    if (order == null) return;
    await _controller.setOrder(order);
  }

  Widget _orderTile(BuildContext context, {required String title, required VisibleRangeOrder value, required VisibleRangeOrder? current}) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, value),
      child: Row(
        children: [
          Icon(current == value ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(title)),
        ],
      ),
    );
  }

  Future<void> _toggleLock() async {
    final range = _controller.range;
    if (range == null) return;
    if (range.locked) {
      await _controller.unlock();
      return;
    }
    await _controller.lockWithPreset(VisibleRangeLockPreset.readOnly);
  }

  void _showBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.visibleRangeManagementBlocked)));
  }
}

/// What the user answered to the replacement warning.
class _OverwriteChoice {
  /// Whether to open the wallpaper chooser again right away.
  final bool reapply;

  /// Whether to stop warning about replacements.
  final bool dismissForever;

  const new({required this.reapply, required this.dismissForever});
}

/// Tells the user that another wallpaper replaced this one.
///
/// The checkbox starts checked: a wallpaper the user keeps is worth one warning,
/// and the default answer should not nag them every time they open the page.
class _OverwriteDialog extends StatefulWidget {
  const new();

  @override
  State<_OverwriteDialog> createState() => _OverwriteDialogState();
}

class _OverwriteDialogState extends State<_OverwriteDialog> {
  bool _dismissForever = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.wallpaperOverwriteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.wallpaperOverwriteBody),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _dismissForever,
            onChanged: (value) => setState(() => _dismissForever = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.wallpaperOverwriteDontAsk),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _OverwriteChoice(reapply: false, dismissForever: _dismissForever)),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _OverwriteChoice(reapply: true, dismissForever: _dismissForever)),
          child: Text(l10n.wallpaperGroupReapply),
        ),
      ],
    );
  }
}
