import 'dart:async';

import 'package:aves/app_mode.dart';
import 'package:aves/features/grouped_wallpaper/engine/grouped_wallpaper_state.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/group_lock_rules.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_lock_surface_status.dart';
import 'package:aves/features/grouped_wallpaper/model/grouped_wallpaper_nav_mode.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_capability.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_sections.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_media_set.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_empty_notice.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_nav_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/grouped_wallpaper_session.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_engine_link.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_page_session.dart';
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
import 'package:aves/features/grouped_wallpaper/view/wallpaper_group_surface_section_key.dart';
import 'package:aves/features/grouped_wallpaper/view/wallpaper_page_selection.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_availability_label.dart';
import 'package:aves/features/grouped_wallpaper/view/widgets/wallpaper_group_tile.dart';
import 'package:aves/features/selection_xor/selection_xor.dart';
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
import 'package:aves/features/visible_range/view/widgets/visible_range_rule_actions.dart';
import 'package:aves/features/visible_range/view/widgets/visible_range_tile.dart';
import 'package:aves/features/wallpaper_lock/services/wallpaper_lock_service.dart';
import 'package:aves/features/wallpaper_lock/view/wallpaper_lock_prompt.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/format.dart';
import 'package:aves/theme/icons.dart';
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

  /// The route the notification's lock button opens while the group is locked.
  ///
  /// It is a route of its own so a cold start lands on the page with the PIN
  /// prompt already open, instead of an extra the app would have to thread
  /// through every entry point.
  static const unlockRouteName = '/wallpaper_groups/unlock';

  /// Whether the page opens on the group the wallpaper is playing.
  ///
  /// A wallpaper gesture opens the view page over the playing group's page, so
  /// that page must show what the view is showing rather than the last group the
  /// user browsed. The bottom-bar destination keeps the browsing session instead.
  final bool selectCurrent;

  /// Whether the page asks for the group PIN as soon as it opens.
  ///
  /// The notification's lock button opens this page while the group is locked, so
  /// the prompt is the reason to be there: cancelling leaves the locked group on
  /// screen, exactly like opening the page by hand and using its menu.
  final bool promptUnlock;

  const new({super.key, this.selectCurrent = false, this.promptUnlock = false});

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
  about,
  applyToMediaSet,
  editRule,
  renameRule,
  deleteSelectedConditions,
  deleteSelectedGroups,
  closePage,
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
  duplicateGroup,
  cancelGalleryRange,
  lockGroup,
  unlockGroup,
  toggleSeparateLockRange,
  switchSurface,
}

/// What closing the page does with the unsaved draft.
enum _CloseChoice {
  save,
  discard,
}

class _GroupedWallpaperPageState extends State<GroupedWallpaperPage> with WidgetsBindingObserver {
  /// Width of one card of the fixed five-column switcher.
  static const int _grid5ColumnCount = 5;

  final ValueNotifier<double> _appBarHeightNotifier = ValueNotifier(0);
  final Set<String> _pendingStats = {};
  Map<String, VisibleRangeCandidateStats> _stats = const {};
  Map<String, Set<CollectionFilter>> _groupFilters = const {};

  /// Each group's saved range, for the card's one-line summary.
  Map<String, VisibleRange?> _groupRanges = const {};
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
  /// It only affects browsing; leaving restores it, and it never changes the
  /// range itself or the wallpaper. The flag lives in the browsing overlay so
  /// the media set (and the strip explaining an empty one) can flip the same
  /// switch instead of keeping a copy the page would not see.
  bool get _gallerySuspended => VisibleRangeGate.overlay?.gallerySuspended ?? false;

  /// The browsing overlay this page claimed, or null before the first sync.
  ///
  /// Releasing by token (not by value) is what keeps a closed page from clearing
  /// the scope a newer page published with the same group.
  Object? _scopeOwner;

  /// Whether the page last published a non-null group scope, for logging only.
  bool _scopeActive = false;

  /// Whether the empty-group dialog is already scheduled for this frame.
  ///
  /// The notice can fire while the page is building (a sync request from the
  /// service); the flag collapses repeated reports into one dialog.
  bool _emptyDialogScheduled = false;

  /// Whether the group switch lock freezes the page.
  ///
  /// The lock freezes one group, not the page: group 0 and the locked group stay
  /// reachable, and closing the page is always allowed, so the user can browse
  /// normally again without unlocking.
  bool get _groupLocked => wallpaperLockService.groupSwitchLocked;

  /// The device's last measured wallpaper capability.
  ///
  /// Kept for the menu's status line and the pre-apply warning; the engine reads
  /// its own copy when it bakes, because the answer changes with the launcher.
  WallpaperCapability _capability = WallpaperCapability.unknown;

  /// Whether this page already asked for the surface-sized re-bake.
  ///
  /// The state only stops saying "wide" once the bake succeeds, so without this
  /// a failing bake would be retried on every resume while the page is open.
  bool _alignRequested = false;

  /// The group the lock froze, if any.
  String? get _lockedGroupId => wallpaperLockService.groupSwitchLockedGroupId;

  /// Whether the selected group's range may be written.
  ///
  /// Two independent locks: the range's own lock and the group switch lock.
  bool get _canEditRange => canEditWallpaperGroupRange(rangeLocked: !_controller.canEdit, groupLocked: _groupLocked);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The bar shows the wallpaper entry for as long as this session lasts.
    groupedWallpaperNavController.openSession();
    _controller = WallpaperGroupRangeController();
    _controller.addListener(_onControllerChanged);
    // Publishing notifies every browsing surface, so it must wait for the first
    // frame: doing it here notified widgets that were still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _syncBrowsingOverlay();
      if (mounted && widget.promptUnlock && _groupLocked) {
        await promptGroupSwitchUnlock(context);
        if (!mounted) return;
      }
      // An empty group reached from a notification or a background run keeps its
      // notice until a page can explain it; this is that page.
      _onEmptyNotice();
    });
    // The browsing scope is shared with the pages pushed over this one, so a
    // strip there can suspend the gallery range and this page must follow.
    VisibleRangeGate.overlayListenable.addListener(_onBrowseScopeChanged);
    visibleRangeController.addListener(_onBrowseScopeChanged);
    wallpaperLockService.addListener(_onLockChanged);
    // The engine reports an empty group here, whatever surface triggered it.
    groupedWallpaperEmptyNotice.addListener(_onEmptyNotice);
    unawaited(_initController());
    unawaited(_refreshEngine());
  }

  /// Loads the groups, then picks the group the page should show.
  ///
  /// The browsing session wins when it has one. On the first open in a process
  /// the page starts on group 0 (no browsing constraint), unless a group is
  /// actually running — the page entered from the wallpaper's own view, or left
  /// open while the app restarts. Adopting the running group keeps the page and
  /// the wallpaper describing the same photos. [GroupedWallpaperPage.selectCurrent]
  /// is the explicit version of that for the view page's backdrop.
  Future<void> _initController() async {
    final hadSession = wallpaperGroupPageSession.initialized;
    await _controller.init();
    if (!mounted) return;
    // A locked group owns the page: opening it anywhere shows the frozen group,
    // never the group that happens to be playing.
    final lockedId = _lockedGroupId;
    if (_groupLocked && lockedId != null && _controller.groups.any((group) => group.id == lockedId)) {
      if (_controller.selectedGroupId != lockedId) await _controller.selectGroup(lockedId);
      return;
    }
    if (hadSession && !widget.selectCurrent) return;
    final runningId = await _runningGroupId();
    if (!mounted || runningId == null) return;
    if (_controller.selectedGroupId == runningId) return;
    if (!canSelectWallpaperGroup(locked: _groupLocked, lockedGroupId: lockedId, targetGroupId: runningId)) return;
    if (_controller.groups.any((group) => group.id == runningId)) {
      await _controller.selectGroup(runningId);
    }
  }

  /// The group the live wallpaper is drawing, or null when it is not running.
  ///
  /// Turned-off wallpaper is not "running": its last frame stays but no group is
  /// in play, so the page must not adopt it as a browsing constraint.
  Future<String?> _runningGroupId() async {
    if (!await wallpaperEngineLink.refreshActive()) return null;
    final state = await wallpaperEngineLink.readState();
    if (state == null || state.status == GroupedWallpaperStatus.disabled) return null;
    final id = state.groupId;
    if (id.isEmpty || id == wallpaperGroupNoneId) return null;
    return id;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the page is not closing it: the session, its bar entry and the
    // group's browsing scope outlive this widget, because the user closes them
    // on purpose from the page's own action. Nothing here may end them — `dispose`
    // also runs when the bar replaces the page for another destination. The
    // listeners go first, so a scope change notified during disposal cannot reach
    // a widget that is going away.
    VisibleRangeGate.overlayListenable.removeListener(_onBrowseScopeChanged);
    visibleRangeController.removeListener(_onBrowseScopeChanged);
    wallpaperLockService.removeListener(_onLockChanged);
    groupedWallpaperEmptyNotice.removeListener(_onEmptyNotice);
    _scopeOwner = null;
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
  /// whether it may show its bar, where it is bound, whether frames pan with the
  /// home pages, and what it is showing.
  Future<void> _refreshEngine() async {
    final active = await wallpaperEngineLink.refreshActive();
    await wallpaperEngineLink.refreshDisabled();
    await wallpaperEngineLink.refreshNotification();
    _capability = await wallpaperEngineLink.capability();
    final state = await wallpaperEngineLink.readState();
    if (!mounted) return;
    // A notification switch or a background run can leave the wallpaper on an
    // empty group before this page is opened; the state is then the only record
    // of why nothing changed.
    if (state != null && state.status == GroupedWallpaperStatus.emptyGroup) {
      groupedWallpaperEmptyNotice.report(groupId: state.groupId, groupName: state.groupName);
    }
    await _warnIfOverwritten(state, active: active);
    await _alignFrameWidth(state);
  }

  /// Replaces a wide frame the device cannot pan, once.
  ///
  /// The engine bakes before the system picker commits, so on a device that only
  /// draws the lock screen the frame can still be the photo's whole width. That
  /// host never receives an offset callback, so nothing would ever ask for the
  /// surface-sized bake; this does, and [GroupedWallpaperSyncResult.unchanged]
  /// keeps every later probe from re-baking. A device that can pan is left alone
  /// here: its launcher reports the step itself.
  Future<void> _alignFrameWidth(GroupedWallpaperState? state) async {
    if (_alignRequested) return;
    if (!wallpaperEngineLink.isPlaying || state == null || !state.hasPhoto) return;
    if (!state.scrollEffect || _capability.panVerdict != CapabilityVerdict.unsupported) return;
    groupedWallpaperLog.i('capability rebake width=surface host=${_capability.host.name} launcher=${_capability.launcherPackage}');
    final result = await wallpaperEngineLink.prepare();
    // A failed bake keeps the wide frame; the next resume retries instead of
    // leaving the visit stuck. `_isLayoutStale` is what makes a successful one a
    // no-op, not this flag.
    if (result != GroupedWallpaperSyncResult.failed) _alignRequested = true;
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

  /// Closes the session and leaves the page.
  ///
  /// This is the only close. Leaving for another destination or pressing back
  /// keeps the session — its bar entry and the group's browsing scope — alive, so
  /// the entry is always there to come back to. An unsaved draft would be
  /// silently lost by leaving, so it asks first: saving applies the draft (and
  /// re-bakes), discarding drops it, cancelling stays on the page.
  ///
  /// Where leaving lands depends on how the page was presented: a page the bar
  /// pushed goes back to the page underneath, while a page that replaced the
  /// range page stays on the range page.
  Future<void> _closePage() async {
    if (!await _confirmClose()) return;
    if (!mounted) return;
    closeGroupedWallpaperSession(owner: _scopeOwner);
    groupedWallpaperLog.i('scope.clear group=${_controller.selectedGroupId} reason=wallpaper-page-closed');
    final navigator = Navigator.maybeOf(context);
    switch (wallpaperPageCloseTarget(groupedWallpaperNavController.mode, canPop: navigator?.canPop() == true)) {
      case WallpaperPageCloseTarget.rangeInPlace:
        // One entry hosts both pages: flipping it back keeps the bar's highlight
        // on the destination the user is looking at.
        visibleRangeDestination.value = VisibleRangeDestination.range;
      case WallpaperPageCloseTarget.pop:
        // The bar pushed this page over another one, so closing returns there
        // instead of stacking the range page on top of it.
        navigator?.pop();
      case WallpaperPageCloseTarget.rangePage:
        // The page replaced the stack, so the range page is its counterpart and
        // the entry goes away with the session.
        await const AvesNavItem(route: VisibleRangePage.routeName).goTo(context, topLevel: true);
    }
  }

  /// Resolves the unsaved draft before the page is closed.
  ///
  /// Returns false when the user cancelled or the save/discard did not complete.
  Future<bool> _confirmClose() async {
    if (!_controller.dirty) return true;
    final l10n = context.l10n;
    final choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.wallpaperGroupCloseConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, _CloseChoice.discard), child: Text(l10n.wallpaperGroupDiscardChanges)),
          // Saving is blocked while the group switch lock is on, exactly like the
          // menu's own "Save changes" entry.
          TextButton(onPressed: _groupLocked ? null : () => Navigator.pop(context, _CloseChoice.save), child: Text(l10n.wallpaperGroupSaveChanges)),
        ],
      ),
    );
    switch (choice) {
      case null:
        return false;
      case _CloseChoice.discard:
        await _controller.discardDraft();
        return true;
      case _CloseChoice.save:
        await _saveDraft();
        return mounted;
    }
  }

  /// Explains once why switching to an empty group changed nothing.
  ///
  /// The engine keeps the frame already on screen instead of replacing it with
  /// the placeholder, so without this the switch looks broken. The notice dedupes
  /// per empty episode, so a sync loop does not make the dialog reappear.
  void _onEmptyNotice() {
    if (!mounted || _emptyDialogScheduled || !groupedWallpaperEmptyNotice.isPending) return;
    _emptyDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _emptyDialogScheduled = false;
      if (!mounted) return;
      final groupName = groupedWallpaperEmptyNotice.groupName;
      if (groupName == null) return;
      final l10n = context.l10n;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.wallpaperGroupEmptyTitle),
          content: Text(l10n.wallpaperGroupEmptyMessage(groupName)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
          ],
        ),
      );
      groupedWallpaperEmptyNotice.dismiss();
    });
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
  /// range like a second visible range, app-wide. The live wallpaper never uses
  /// this; it reads the saved group range alone.
  ///
  /// The suspension flag is read back from the overlay so a strip on a page
  /// pushed over this one keeps its choice when the group changes here.
  void _syncBrowsingOverlay() {
    // The session owns the scope. Closing it from the navigation settings can run
    // while this page is still in the stack (the drawer opens settings over it),
    // and a later controller change must not publish the scope again.
    if (!groupedWallpaperNavController.sessionActive) {
      if (_scopeOwner != null) {
        _scopeOwner = null;
        VisibleRangeGate.clearWallpaperScope();
        groupedWallpaperLog.i('scope.clear group=${_controller.selectedGroupId} reason=session-closed');
      }
      return;
    }
    final groupFilter = _controller.range?.resolve();
    // Group 0 means "no group restriction": the overlay is dropped rather than
    // kept empty, so browsing falls back to the gallery range alone.
    final next = groupFilter == null
        ? null
        : VisibleRangeBrowsingOverlay(
            groupFilter: groupFilter,
            gallerySuspended: _gallerySuspended,
          );
    final owner = _scopeOwner;
    if (owner == null) {
      _scopeOwner = VisibleRangeGate.claimWallpaperScope(next);
    } else if (!VisibleRangeGate.publishWallpaperScope(owner, next)) {
      // A newer page owns the scope and already describes the screen.
      return;
    }
    final wasActive = _scopeActive;
    _scopeActive = next != null;
    if (next == null) {
      if (wasActive) groupedWallpaperLog.i('scope.clear group=${_controller.selectedGroupId} reason=group-0');
      return;
    }
    final gallery = visibleRangeController.gallery;
    groupedWallpaperLog.i(
      'scope.publish group=${_controller.selectedGroupId} gallery=${gallery.isRestricted} locked=${gallery.locked} suspended=${next.gallerySuspended} filter=${next.groupFilter?.key}',
    );
  }

  /// Re-reads a browsing scope changed elsewhere (the media set's strip, or the
  /// gallery range itself), since both change what this page previews.
  void _onBrowseScopeChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_refreshResultStats());
  }

  /// Follows the group lock when it is set or cleared from a menu or settings.
  ///
  /// Unlocking leaves the page on the group that was locked; locking re-opens
  /// that group even if the page had moved to group 0, so the frozen group is
  /// what the user sees and cannot wander away from.
  void _onLockChanged() {
    if (!mounted) return;
    final lockedId = _lockedGroupId;
    if (_groupLocked && lockedId != null && _controller.selectedGroupId != lockedId && _controller.groups.any((group) => group.id == lockedId)) {
      unawaited(_controller.selectGroup(lockedId));
    }
    setState(() {});
    unawaited(_refreshGroupFilters());
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

  /// Count and cover of what browsing yields for the selected group.
  ///
  /// The preview follows the browsing gate, so it shows the gallery range joined
  /// with the group instead of the group alone: the card above still counts what
  /// the live wallpaper may use, and the two differ exactly when the gallery
  /// range narrows browsing. A user who sees an empty media set then sees the
  /// same zero here instead of a number the app never displays.
  Future<void> _refreshResultStats() async {
    final range = _controller.range;
    final token = ++_resultToken;
    if (range == null) {
      setState(() => _resultStats = null);
      return;
    }
    final filter = VisibleRangeGate.filter;
    final filters = filter == null ? const <CollectionFilter>{} : <CollectionFilter>{filter};
    final stats = await VisibleRangeCandidateStatsLoader.load([filters]);
    if (!mounted || token != _resultToken) return;
    setState(() => _resultStats = stats.values.firstOrNull);
  }

  /// The media set behind every group card, so a card without a note can show
  /// its image count. Group 0 is every image.
  ///
  /// The ranges are kept too: the card states the range in one line, since a
  /// restriction deep in the page is what usually explains an empty wallpaper.
  Future<void> _refreshGroupFilters() async {
    final next = <String, Set<CollectionFilter>>{
      wallpaperGroupNoneId: {MimeFilter.image},
    };
    final ranges = <String, VisibleRange?>{wallpaperGroupNoneId: null};
    for (final group in _controller.groups) {
      final range = await _controller.groupController.groupRange(group.id);
      final filter = wallpaperMediaSetFilter(range);
      next[group.id] = filter == null ? {MimeFilter.image} : {filter};
      ranges[group.id] = range;
    }
    if (!mounted) return;
    setState(() {
      _groupFilters = next;
      _groupRanges = ranges;
    });
    await _refreshStats();
  }

  Future<void> _refreshStats() async {
    final filtersByKey = <String, Set<CollectionFilter>>{};
    // Every condition is stored once, so one pass over the pool covers both
    // surfaces, including the conditions no surface marks.
    final pool = _controller.pool;
    if (pool != null) {
      for (final section in buildWallpaperGroupPoolSections(pool: pool, active: _controller.surface)) {
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
    final missing = filtersByKey.entries.where((entry) => !_stats.containsKey(entry.key) && !_pendingStats.contains(entry.key)).map((entry) => MapEntry(entry.key, entry.value)).toList();
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
          // so a "select all" must not pick them up either. The list follows the
          // current selection scope, so the page's two grids never mix.
          itemBuilder: () => _selectionItems(sections),
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
                      if (filter is WallpaperGroupFilter) return filter.groupId != null && !_groupLocked;
                      return filter is VisibleRangeCandidateFilter && !filter.summary && _isSelectable(filter.candidate);
                    },
                    // Group cards and conditions are two different multi-select
                    // states: a range must not cross from one into the other.
                    sameSelectionScope: _sameSelectionScope,
                    tileBuilder: _buildTile,
                    // A split group repeats each surface as its own section, so
                    // the footer would be a third copy of the same conditions.
                    footerBuilder: _controller.separateLockRange || _controller.activeStyle == VisibleRangeActiveStyle.section ? null : _buildFooter,
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
    if (_controller.selectedGroupId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.wallpaperGroupNoneBody, textAlign: TextAlign.center),
        ),
      );
    }
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
        final selecting = _selection.isSelecting && wallpaperPageItemInScope(_scope, isGroup: true);
        // While either grid is selecting, the switcher must not change the viewed
        // group: that would reset the selection mid-edit.
        final browsing = !_selection.isSelecting;
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
                      selected: browsing && viewedId == null,
                      onSelected: browsing ? (_) => unawaited(_controller.selectGroup(null)) : null,
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
                            avatar: selecting ? Icon(selectedIds.contains(group.id) ? AIcons.selected : AIcons.unselected, size: 18) : _groupStateIcon(context, group),
                            label: Text('${group.number}  ${wallpaperGroupName(context, group)}'),
                            selected: selecting ? selectedIds.contains(group.id) : browsing && viewedId == group.id,
                            labelStyle: group.enabled && _groupSelectable(group.id) ? null : TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            showCheckmark: false,
                            // A locked group cannot be opened: the chip greys out
                            // and the tap does nothing, while group 0 and the
                            // locked group stay live.
                            onSelected: !browsing || !_groupSelectable(group.id) ? null : (_) => _onGroupCardTap(group.id),
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
        final selecting = _selection.isSelecting && wallpaperPageItemInScope(_scope, isGroup: true);
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
                          // A locked group is dimmed like a disabled one: the card
                          // still describes the range, but it cannot be opened.
                          child: Opacity(
                            opacity: _groupSelectable(groupId == wallpaperGroupNoneId ? null : groupId) ? 1 : .4,
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

  /// Which grid the page's current multi-selection belongs to.
  ///
  /// Group cards select what to manage, condition tiles select what to apply or
  /// edit. They share one grid and one [Selection], so the page has to keep the
  /// two states apart itself.
  WallpaperPageSelectionScope get _scope => wallpaperPageSelectionScope(_selection.selectedItems.map((item) => item.filter));

  /// The rows the current selection may hold, in display order.
  ///
  /// A selection already in play only offers its own scope, so "select all" can
  /// never mix the group cards with the conditions.
  List<FilterGridItem<CollectionFilter>> _selectionItems(Map<ChipSectionKey, List<FilterGridItem<CollectionFilter>>> sections) {
    final scope = _scope;
    if (_selection.isSelecting && scope == WallpaperPageSelectionScope.none) return const [];
    return sections.values.expand((list) => list).where((item) {
      final filter = item.filter;
      if (filter is WallpaperGroupFilter) {
        return filter.groupId != null && !_groupLocked && wallpaperPageItemInScope(scope, isGroup: true);
      }
      return filter is VisibleRangeCandidateFilter && !filter.summary && _isSelectable(filter.candidate) && wallpaperPageItemInScope(scope, isGroup: false);
    }).toList();
  }

  /// Whether [item] may join the selection that already holds [selected].
  ///
  /// A fresh selection takes the scope of the pressed item; an existing one keeps
  /// its own, so a press in the other grid does nothing.
  bool _sameSelectionScope(FilterGridItem<CollectionFilter> item, Set<FilterGridItem<CollectionFilter>> selected) {
    final scope = wallpaperPageSelectionScope(selected.map((item) => item.filter));
    final effective = scope == WallpaperPageSelectionScope.none ? wallpaperPageItemScope(item.filter) : scope;
    return wallpaperPageItemInScope(effective, isGroup: item.filter is WallpaperGroupFilter);
  }

  /// The selectable group cards in display order, for the XOR-range gesture.
  List<FilterGridItem<CollectionFilter>> _groupItems() => [
        if (!_groupLocked)
          for (final group in _controller.groups) _groupItem(group.id),
      ];

  /// A group card switches the viewed group, or joins the selection while the
  /// page is selecting groups. Group 0 is a view choice and is never selectable.
  void _onGroupCardTap(String? groupId) {
    if (_selection.isSelecting) {
      // A condition selection must not grow a group card: switching what is
      // managed mid-edit is exactly what the two-scope rule prevents.
      if (_scope == WallpaperPageSelectionScope.conditions) return;
      if (groupId != null && !_groupLocked) _selection.toggleSelection(_groupItem(groupId));
      return;
    }
    if (!canSelectWallpaperGroup(locked: _groupLocked, lockedGroupId: _lockedGroupId, targetGroupId: groupId)) {
      _showGroupLocked();
      return;
    }
    unawaited(_controller.selectGroup(groupId));
  }

  /// Long press starts or extends the group selection, mirroring the condition
  /// tiles' selection mode. Group selection leads to management actions, which a
  /// locked group freezes.
  void _onGroupCardLongPress(String? groupId) {
    if (groupId == null || _groupLocked) return;
    // A condition selection owns the gesture: a press here must not add groups.
    if (_selection.isSelecting && _scope == WallpaperPageSelectionScope.conditions) return;
    final items = _groupItems();
    final target = items.firstWhereOrNull((item) => _selection.isSameItem(item, _groupItem(groupId)));
    if (target == null) return;
    _selection.rangeXorTo(items, target);
  }

  void _showGroupLocked() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.wallpaperGroupLockedSwitch)));
  }

  /// Whether the switcher may open [groupId] (null is group 0).
  bool _groupSelectable(String? groupId) => canSelectWallpaperGroup(locked: _groupLocked, lockedGroupId: _lockedGroupId, targetGroupId: groupId);

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
      range: _groupRanges[groupId],
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
    final pool = _controller.pool;
    final activeRange = _controller.range;
    if (pool == null || activeRange == null) return result;
    final surface = _controller.surface;
    // The three condition sections are the pool: every condition once, whatever
    // surface marks it. Only the lamped surface's marks are editable; the other
    // surface's marks stay visible on the same tiles.
    for (final section in buildWallpaperGroupPoolSections(pool: pool, active: surface)) {
      final real = section.candidates.where((candidate) => !candidate.placeholder).toList();
      final countText = switch (section.kind) {
        // The base is exclusive: the section already says so, and the count of
        // the control tiles would only confuse it with conditions.
        VisibleRangeCandidateKind.base => '',
        VisibleRangeCandidateKind.restriction || VisibleRangeCandidateKind.supplement => real.isEmpty ? '' : '${real.where((candidate) => candidate.active).length}/${real.length}',
      };
      result[VisibleRangeSectionKey(context, section.kind, countText: countText, supplementsOutside: pool.order.isIntersectFirst)] = [
        for (final candidate in section.candidates) FilterGridItem<CollectionFilter>(VisibleRangeCandidateFilter(candidate), null),
      ];
    }
    if (_controller.separateLockRange) {
      // The two surfaces end the page: the lamp says which one the sections above
      // are editing, and each one lists what it actually applies. The lamped
      // surface also previews its result, so the page needs no third "current
      // range" section repeating the same conditions.
      for (final entry in [
        (surface: WallpaperSurface.home, range: _controller.homeRange, active: !surface.isLock),
        (surface: WallpaperSurface.lock, range: _controller.lockRange, active: surface.isLock),
      ]) {
        final range = entry.range;
        if (range == null) continue;
        final candidates = buildWallpaperGroupSurfaceCandidates(range: range, includeResult: entry.active);
        final countText = '${candidates.where((candidate) => !candidate.placeholder && !candidate.isGallery).length}';
        result[WallpaperGroupSurfaceSectionKey(context, surface: entry.surface, active: entry.active, countText: countText)] = [
          for (final candidate in candidates) FilterGridItem<CollectionFilter>(VisibleRangeCandidateFilter(candidate.copyWithReadOnly(true), summary: true, surface: entry.surface), null),
        ];
      }
    } else if (_controller.activeStyle == VisibleRangeActiveStyle.section) {
      final active = buildWallpaperGroupSurfaceCandidates(range: activeRange, includeResult: true);
      result[VisibleRangeActiveSectionKey(context, restricted: activeRange.isRestricted)] = [
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
            selecting: _selection.isSelecting && wallpaperPageItemInScope(_scope, isGroup: true),
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
    // `All images` is a base slot, not a condition, so it must not be selectable;
    // the group cards above are another selection scope entirely.
    final selectable = !candidateFilter.summary && _isSelectable(candidate) && wallpaperPageItemInScope(_scope, isGroup: false);
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
          selectable: selectable,
          // The shared selector resolves the pressed row from the layout, not
          // from its own selectable list, so a tile that must not be selected
          // has to consume the long press itself.
          onLongPress: selectable ? null : () {},
          // The pool tiles carry both surface marks; a surface summary already
          // is one surface, so it shows none.
          surfaceMarks: _controller.separateLockRange && !candidate.placeholder && candidateFilter.surface == null
              ? (
                  home: WallpaperConditionSurfaces.contains(candidate.surfaces, WallpaperSurface.home),
                  lock: WallpaperConditionSurfaces.contains(candidate.surfaces, WallpaperSurface.lock),
                )
              : null,
          selecting: _selection.isSelecting && wallpaperPageItemInScope(_scope, isGroup: false),
          selected: _selection.selectedItems.contains(item),
          labelOverride: _labelOverride(context, candidate),
          onTap: () => _onTileTap(item),
        ),
      ),
    );
  }

  /// The group page selects only real conditions: the group's own base and its
  /// rules. Placeholders and the result preview are controls, not data.
  bool _isSelectable(VisibleRangeCandidate candidate) => !candidate.readOnly && (candidate.rule != null || isWallpaperGroupBaseCandidate(candidate));

  /// Cover chips have no room for long text, so the empty-section slots use the
  /// short label in every layout.
  String _labelOverride(BuildContext context, VisibleRangeCandidate candidate) {
    if (!candidate.placeholder) return '';
    return context.l10n.wallpaperGroupSectionNone;
  }

  Widget _buildFooter(BuildContext context) {
    final range = _controller.range;
    if (range == null) return const SizedBox();
    final activeBase = range.baseActive && range.baseFilters.isNotEmpty ? VisibleRangeCandidate.customBase(name: range.baseName, filters: range.baseFilters) : null;
    final activeRules = [
      for (final kind in range.order.isIntersectFirst ? [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement] : [VisibleRangeRuleKind.supplement, VisibleRangeRuleKind.restriction])
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
    if (!_canEditRange) {
      _showBlocked();
      return;
    }
    unawaited(_controller.toggleRuleSurface(rule.id, _controller.surface));
  }

  void _cancelBase() {
    if (!_canEditRange) {
      _showBlocked();
      return;
    }
    // Cancelling the base only clears this surface's mark: the filters stay in
    // the pool, so the other surface keeps them and this one can put them back.
    unawaited(_controller.setBaseSurface(_controller.surface, false));
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
    // A surface summary is a selector, not an editor: tapping it switches which
    // surface the pool sections above edit.
    final sectionSurface = candidateFilter.surface;
    if (sectionSurface != null) {
      if (sectionSurface != _controller.surface) unawaited(_controller.switchSurface(sectionSurface));
      return;
    }
    if (candidate.readOnly) return;
    if (_selection.isSelecting) {
      // Group management owns the selection: a condition must not join it.
      if (_scope == WallpaperPageSelectionScope.groups) return;
      if (_isSelectable(candidate)) _selection.toggleSelection(item);
      return;
    }
    if (!_canEditRange) {
      _showBlocked();
      return;
    }
    final surface = _controller.surface;
    if (candidateFilter.summary) {
      // The footer repeats the conditions this surface applies; tapping one
      // switches it off for this surface, like the tile in the section above.
      final rule = candidate.rule;
      if (rule != null) {
        unawaited(_controller.toggleRuleSurface(rule.id, surface));
      } else if (isWallpaperGroupBaseCandidate(candidate)) {
        unawaited(_controller.setBaseSurface(surface, false));
      }
      return;
    }
    // Placeholders are controls, not conditions: an empty section slot does
    // nothing.
    if (candidate.placeholder) return;
    switch (candidate.kind) {
      case VisibleRangeCandidateKind.base:
        if (candidate.isUnrestricted) {
          // 「All images」 clears this surface's base mark; the filters stay in the
          // pool for the other surface, so nothing is lost.
          final pool = _controller.pool;
          if (pool != null && WallpaperConditionSurfaces.contains(pool.baseSurfaces, surface)) {
            unawaited(_controller.setBaseSurface(surface, false));
          }
        } else if (isWallpaperGroupBaseCandidate(candidate)) {
          final pool = _controller.pool;
          final marked = pool != null && WallpaperConditionSurfaces.contains(pool.baseSurfaces, surface);
          unawaited(_controller.setBaseSurface(surface, !marked));
        }
      case VisibleRangeCandidateKind.restriction:
      case VisibleRangeCandidateKind.supplement:
        final rule = candidate.rule;
        if (rule != null) unawaited(_controller.toggleRuleSurface(rule.id, surface));
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
        if (groups.isNotEmpty && !_groupLocked)
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
        if (groups.isNotEmpty && !_groupLocked) _menuItem(_PageAction.deleteSelectedGroups, AIcons.delete, context.l10n.wallpaperGroupDeleteSelected),
      ];
    }
    return _menuEntries(context);
  }

  List<VisibleRangeCandidate> _selectedCandidates(Selection<FilterGridItem<CollectionFilter>> selection) {
    if (!selection.isSelecting) return const [];
    // The inactive surface is a read-only summary. Its tiles are not meant to
    // enter the selection at all, but the shared grid selector resolves the
    // pressed row from the layout rather than from its selectable list, so this
    // is the one place that guarantees no action is ever applied to it.
    return [
      for (final item in selection.selectedItems)
        if (item.filter case VisibleRangeCandidateFilter filter)
          if (!filter.candidate.readOnly) filter.candidate,
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
  ///
  /// A group is remembered by its pool id, because the condition is shared by
  /// both surfaces and the write-back must edit it once.
  Future<void> _applySelectionToMediaSet() async {
    final range = _controller.range;
    if (!_selection.isSelecting || range == null) return;
    final candidates = _selectedCandidates(_selection);
    if (candidates.isEmpty) return;
    _selection.browse();
    await applyVisibleRangeCandidates(context, rangeId: _controller.pool?.id ?? range.id, candidates: candidates);
  }

  Future<void> _deleteSelectedConditions() async {
    final rules = _selectedRules(_selection);
    final base = _selectionHasBase(_selection);
    if (rules.isEmpty && !base) return;
    if (!_canEditRange) {
      _showBlocked();
      return;
    }
    _selection.browse();
    await _controller.deleteConditions(base: base, ruleIds: rules.map((rule) => rule.id).toSet());
  }

  /// Deletes the selected group cards. The group controller keeps at least one
  /// group, so a selection that would empty the list is refused as a whole.
  Future<void> _deleteSelectedGroups() async {
    // A group that was selected before the lock was set must not be deleted
    // behind the lock's back.
    if (_groupLocked) {
      _showGroupLocked();
      return;
    }
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
    if (!_canEditRange) {
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
    final action = await showVisibleRangeRuleActions(context, rule: rule, canEdit: _canEditRange);
    if (action == null || !mounted) return;
    switch (action) {
      case VisibleRangeRuleAction.rename:
        await _renameRule(rule);
      case VisibleRangeRuleAction.moveToBase:
        if (!_canEditRange) {
          _showBlocked();
          return;
        }
        _selection.browse();
        await _controller.moveRuleToBase(rule.id, name: visibleRangeRuleLabel(context, rule));
      case VisibleRangeRuleAction.moveToRestriction:
      case VisibleRangeRuleAction.moveToSupplement:
        if (!_canEditRange) {
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
        if (!_canEditRange) {
          _showBlocked();
          return;
        }
        _selection.browse();
        await _controller.deleteConditions(ruleIds: {rule.id});
    }
  }

  /// Opens the media set with the rule's conditions, replacing what it shows or
  /// appending to it. Nothing is written: the user keeps working there.
  ///
  /// The target is remembered exactly like the multi-select path, so the pin
  /// sheet can write the current filters back over this rule. A group is
  /// addressed by its pool, whatever surface is being edited, because the
  /// condition is shared.
  Future<void> _activateRule(VisibleRangeRule rule, {required bool replace}) async {
    final range = _controller.range;
    if (range == null) return;
    final rangeId = _controller.pool?.id ?? range.id;
    _selection.browse();
    await applyVisibleRangeCandidates(
      context,
      rangeId: rangeId,
      candidates: [VisibleRangeCandidate.fromRule(rule)],
      replace: replace,
    );
  }

  List<PopupMenuEntry<_PageAction>> _menuEntries(BuildContext context) {
    final l10n = context.l10n;
    final group = _selectedGroup;
    final range = _controller.range;
    final locked = range?.locked ?? false;
    final canDelete = _controller.groups.length > 1;
    final gallery = visibleRangeController.gallery;
    // Ignoring the gallery range is what the range's lock protects, so the entry
    // stays available and asks for the PIN; restoring never needs one.
    final canSuspendGallery = gallery.isRestricted;
    final engineActive = wallpaperEngineLink.isActive;
    return [
      // Draft actions come first: nothing below reaches the database until the
      // user saves, so the state and its two follow-ups stay together.
      _menuItem(
        _PageAction.saveChanges,
        AIcons.save,
        l10n.wallpaperGroupSaveChanges,
        enabled: _controller.dirty && !_groupLocked,
        subtitle: _groupLocked
            ? l10n.wallpaperGroupLockedSubtitle
            : _controller.dirty
            ? l10n.wallpaperGroupDraftUnsaved
            : null,
      ),
      // Discarding is the exact counterpart of saving, so the two stay together.
      _menuItem(
        _PageAction.discardChanges,
        AIcons.discard,
        l10n.wallpaperGroupDiscardChanges,
        enabled: _controller.dirty && !_groupLocked,
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
          enabled: wallpaperEngineLink.isAttached && group.enabled && !_groupLocked,
          subtitle: _groupLocked
              ? l10n.wallpaperGroupLockedSubtitle
              : wallpaperEngineLink.isAttached
              ? (group.current && wallpaperEngineLink.isPlaying
                    // A host that only draws the lock screen is still "playing",
                    // but saying so plainly is what explains a static home
                    // wallpaper.
                    ? (_capability.host == WallpaperHost.lock ? l10n.wallpaperGroupStatusLockOnly : l10n.wallpaperGroupAlreadyPlaying)
                    : null)
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
      if (group != null) ...[
        // The decoy surface is opt-in per group: the home range stays mandatory,
        // and turning the split off only hides the lock range.
        _menuItem(
          _PageAction.toggleSeparateLockRange,
          group.separateLockRange ? AIcons.checked : AIcons.unselected,
          l10n.wallpaperGroupSeparateLockRange,
          enabled: !_groupLocked,
          subtitle: _groupLocked ? l10n.wallpaperGroupLockedSubtitle : null,
        ),
        if (group.separateLockRange)
          _menuItem(
            _PageAction.switchSurface,
            AIcons.visibleRangeActive,
            _controller.surface.isLock ? l10n.wallpaperGroupShowHomeRange : l10n.wallpaperGroupShowLockRange,
            subtitle: _controller.surface.isLock ? l10n.wallpaperGroupSurfaceLock : l10n.wallpaperGroupSurfaceHome,
          ),
      ],
      const PopupMenuDivider(),
      // The counterpart of the visible range page's "Open wallpaper groups":
      // closing keeps the unsaved draft from being lost, then returns to the page
      // the user came from. This is the only way to end the session, so the bar
      // entry and the group's browsing scope go away together.
      _menuItem(_PageAction.closePage, AIcons.cancel, l10n.wallpaperGroupClosePage),
      if (gallery.isRestricted)
        _menuItem(
          _PageAction.cancelGalleryRange,
          gallery.locked ? AIcons.locked : AIcons.visibleRangeActive,
          _gallerySuspended ? l10n.wallpaperGroupRestoreGalleryRange : l10n.wallpaperGroupCancelGalleryRange,
          enabled: canSuspendGallery,
          subtitle: gallery.locked && !_gallerySuspended ? l10n.visibleRangeWhenLocked : null,
        ),
      const PopupMenuDivider(),
      // The group lock is the way in and out; it stays available whatever the
      // page shows, because group 0 is still reachable while locked.
      if (_groupLocked)
        _menuItem(_PageAction.unlockGroup, AIcons.unlocked, l10n.wallpaperGroupUnlockCurrent, subtitle: l10n.wallpaperGroupLockedSubtitle)
      else if (group != null)
        _menuItem(_PageAction.lockGroup, AIcons.locked, l10n.wallpaperGroupLockCurrent),
      if (group != null) ...[
        _menuItem(
          _PageAction.toggleEnabled,
          group.enabled ? AIcons.unselected : AIcons.checked,
          group.enabled ? l10n.wallpaperGroupDisable : l10n.wallpaperGroupEnable,
          enabled: !_groupLocked,
          subtitle: _groupLocked ? l10n.wallpaperGroupLockedSubtitle : null,
        ),
        _menuItem(_PageAction.moveUp, AIcons.up, l10n.wallpaperGroupMoveUp, enabled: !_groupLocked),
        _menuItem(_PageAction.moveDown, AIcons.down, l10n.wallpaperGroupMoveDown, enabled: !_groupLocked),
        const PopupMenuDivider(),
        _menuItem(_PageAction.rename, AIcons.edit, l10n.wallpaperGroupRename, enabled: !_groupLocked),
        _menuItem(
          _PageAction.duplicateGroup,
          AIcons.copy,
          l10n.wallpaperGroupDuplicate,
          enabled: !locked && !_groupLocked,
          subtitle: _groupLocked
              ? l10n.wallpaperGroupLockedSubtitle
              : locked
              ? l10n.visibleRangeManagementBlocked
              : null,
        ),
      ],
      _menuItem(_PageAction.add, AIcons.add, l10n.wallpaperGroupAdd, enabled: !_groupLocked),
      if (group != null) _menuItem(_PageAction.delete, AIcons.delete, l10n.wallpaperGroupDelete, enabled: canDelete && !_groupLocked),
      const PopupMenuDivider(),
      if (range != null) ...[
        _menuItem(_PageAction.order, AIcons.sortOrder, l10n.visibleRangeOrder, enabled: !_groupLocked),
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

  Future<void> _onMenuSelected(_PageAction action) async {
    final group = _selectedGroup;
    switch (action) {
      case _PageAction.closePage:
        await _closePage();
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
      case _PageAction.toggleSeparateLockRange:
        if (group != null) await _toggleSeparateLockRange(group);
      case _PageAction.switchSurface:
        _selection.browse();
        await _controller.switchSurface(_controller.surface.isLock ? WallpaperSurface.home : WallpaperSurface.lock);
        _syncBrowsingOverlay();
        await _refreshStats();
      case _PageAction.duplicateGroup:
        if (group != null) await _duplicateGroup(group);
      case _PageAction.cancelGalleryRange:
        await _toggleGallerySuspension();
      case _PageAction.lockGroup:
        await _lockCurrentGroup();
      case _PageAction.unlockGroup:
        await promptGroupSwitchUnlock(context);
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
    // A locked group cannot leave itself: the menu entry is greyed, and this
    // guard covers a stale menu or a notification action.
    if (wallpaperLockService.groupSwitchLocked) return;
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
    final result = await wallpaperEngineLink.prepare();
    await _refreshEngine();
    if (!mounted) return;
    if (!wallpaperEngineLink.isActive) {
      await _setWallpaper();
      return;
    }
    // The group is now current in the database but has no photo: the wallpaper
    // deliberately keeps the previous frame, and the empty notice explains it.
    if (result == GroupedWallpaperSyncResult.empty) return;
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
    if (result == GroupedWallpaperSyncResult.empty) {
      // The notice owns the explanation. If this empty episode was already
      // explained, a short message keeps the action from looking ignored without
      // showing the dialog again.
      if (!groupedWallpaperEmptyNotice.isPending) _showMessage(context.l10n.wallpaperGroupSyncEmpty);
      return;
    }
    _showMessage(
      switch (result) {
        GroupedWallpaperSyncResult.baked => context.l10n.wallpaperGroupSyncDone,
        GroupedWallpaperSyncResult.disabled => context.l10n.wallpaperGroupSyncDisabled,
        GroupedWallpaperSyncResult.unchanged => context.l10n.wallpaperGroupSyncDone,
        GroupedWallpaperSyncResult.notActive => context.l10n.wallpaperGroupSyncInactive,
        GroupedWallpaperSyncResult.failed => context.l10n.wallpaperGroupSyncFailed,
        GroupedWallpaperSyncResult.empty => context.l10n.wallpaperGroupSyncEmpty,
      },
    );
  }

  /// Opens the system live-wallpaper chooser for the grouped service.
  ///
  /// Warns once per device first. The picker takes over the screen, so the
  /// engine state is re-read on resume rather than here; this only reports an
  /// OEM that has no picker at all.
  Future<void> _setWallpaper() async {
    if (!await _confirmCapability()) return;
    final opened = await wallpaperEngineLink.openChooser();
    if (!mounted || opened) return;
    _showMessage(context.l10n.wallpaperGroupChooserUnavailable);
  }

  /// Warns before applying on a device that cannot pan this wallpaper.
  ///
  /// Only a measured [CapabilityVerdict.unsupported] warns: an unbound device or
  /// a launcher that has not reported its step yet is asked to apply as usual,
  /// so a phone that does pan is never told otherwise. The warning is stored per
  /// device + launcher, so changing the launcher asks once more.
  Future<bool> _confirmCapability() async {
    _capability = await wallpaperEngineLink.capability();
    if (!_capability.warnsBeforeApply) return true;
    if (!await _controller.groupController.shouldWarnCapability(_capability.warningKey)) return true;
    if (!mounted) return false;
    final l10n = context.l10n;
    groupedWallpaperLog.i(
      'capability warn host=${_capability.host.name} launcher=${_capability.launcherPackage} '
      'span=${_capability.scrollSpan} step=${_capability.scrollStep} moved=${_capability.scrollOffsetMoved}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.wallpaperGroupCapabilityTitle),
        content: Text(
          [
            if (_capability.hostVerdict == CapabilityVerdict.unsupported) l10n.wallpaperGroupCapabilityNoHome,
            if (_capability.panVerdict == CapabilityVerdict.unsupported) l10n.wallpaperGroupCapabilityNoPan,
            // The sentence is a promise about this bake. MIUI on a first install
            // is `host=none` + `panVerdict=unknown`, which still bakes wide until
            // the page sees the committed host, so it must not promise narrow.
            if (!_capability.bakesWide) l10n.wallpaperGroupCapabilityNarrow,
          ].join('\n\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.wallpaperGroupCapabilityContinue)),
        ],
      ),
    );
    if (confirmed != true) return false;
    await _controller.groupController.markCapabilityWarned(_capability.warningKey);
    return true;
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
          controller: _controller.groupController,
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
          controller: _controller.groupController,
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

  /// Turns the group's decoy lock surface on or off.
  ///
  /// The split is a saved assignment, not a request to turn the wallpaper on: it
  /// can be prepared while the grouped wallpaper is off, so the user picks what
  /// home and lock will show before activating it. Like every other edit on this
  /// page it waits for "save changes", which is also what re-bakes the running
  /// wallpaper.
  ///
  /// The device-support check only makes sense while this wallpaper is actually
  /// the system wallpaper — an inactive engine would report whatever the current
  /// wallpaper is — so it is skipped otherwise instead of pushing the user into
  /// the wallpaper chooser just to assign a range.
  Future<void> _toggleSeparateLockRange(WallpaperGroup group) async {
    if (_groupLocked) {
      _showBlocked();
      return;
    }
    final enabling = !group.separateLockRange;
    _selection.browse();
    await _controller.setSeparateLockRange(enabling);
    if (!enabling || !wallpaperEngineLink.isActive || !mounted) return;
    final status = await wallpaperEngineLink.lockSurfaceStatus();
    if (!mounted) return;
    if (status == GroupedWallpaperLockSurfaceStatus.none || status == GroupedWallpaperLockSurfaceStatus.other) {
      await _showLockSurfaceUnsupported(status);
    }
  }

  /// Explains that this device will not draw the decoy, with a way to fix it.
  ///
  /// A device older than Android 14 cannot report the lock wallpaper at all and
  /// answers `unknown`: there is nothing useful to warn about, so the About page
  /// carries the explanation instead of a dialog.
  Future<void> _showLockSurfaceUnsupported(GroupedWallpaperLockSurfaceStatus status) async {
    final l10n = context.l10n;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(status == GroupedWallpaperLockSurfaceStatus.other ? l10n.wallpaperGroupLockSurfaceOther : l10n.wallpaperGroupLockSurfaceUnsupported),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(MaterialLocalizations.of(context).okButtonLabel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.wallpaperGroupLockSurfaceOpenChooser)),
        ],
      ),
    );
    if (open == true) await wallpaperEngineLink.openChooser();
  }

  /// Copies [group] into a new group and opens the copy.
  ///
  /// A locked group is refused here and again in the controller: its range is
  /// read-only, so a copy would clone content the user froze.
  Future<void> _duplicateGroup(WallpaperGroup group) async {
    if (!_canEditRange) {
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Temporarily stops applying the gallery range to browsing.
  ///
  /// It is a view choice only: nothing is written, and closing the page restores
  /// it. Ignoring a locked range needs the range's PIN; restoring never does.
  /// The value is published in the browsing overlay, so the media set's strip
  /// flips the same switch and its listener repaints this page.
  Future<void> _toggleGallerySuspension() async {
    if (!_gallerySuspended && visibleRangeController.gallery.locked) {
      if (!await ensureVisibleRangeUnlocked(context)) return;
      if (!mounted) return;
    }
    VisibleRangeGate.setGallerySuspended(!_gallerySuspended);
  }

  /// Freezes the group on screen: only it and group 0 stay reachable.
  ///
  /// Locking is direct (no PIN); the recorded group is what the page re-opens on
  /// and what the notification bar refuses to leave.
  Future<void> _lockCurrentGroup() async {
    final id = _controller.selectedGroupId;
    if (id == null) return;
    await wallpaperLockService.lockGroup(id);
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

  void _showBlocked() {
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_groupLocked ? l10n.wallpaperGroupLockedSwitch : l10n.visibleRangeManagementBlocked)));
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
