import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_page_session.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart' show VisibleRangeActiveStyle;
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

/// Edits the selected wallpaper group's visible range for the wallpaper page.
///
/// The page is the range editor with a group switcher on top, so this controller
/// is the group-scoped counterpart of [VisibleRangeController]: every write goes
/// through [WallpaperGroupController.saveGroupRange], which keeps the
/// "one group owns exactly one `wallpaper` range" invariant in one place.
///
/// The page's own view preferences (the active-style form) are stored apart from
/// the visible-range page's, so the two pages can look different: a list here and
/// a grid there, for example. The layout itself is already isolated by the page's
/// route key.
class WallpaperGroupRangeController extends ChangeNotifier {
  /// AppMeta key of this page's active-style form.
  static const keyActiveStyle = 'wallpaper.page.activeStyle';

  /// AppMeta key of this page's group switcher style.
  static const keySwitcherStyle = 'wallpaper.page.groupSwitcherStyle';

  final WallpaperGroupController groupController;
  final AppDatabase? injectedDatabase;

  new({
    WallpaperGroupController? groupController,
    this.injectedDatabase,
  }) : groupController = groupController ?? wallpaperGroupController;

  AppDatabase? _db;
  bool _initialized = false;
  bool _loading = false;
  String? _selectedGroupId;
  VisibleRange? _range;
  VisibleRangeActiveStyle _activeStyle = VisibleRangeActiveStyle.section;
  WallpaperGroupSwitcherStyle _switcherStyle = WallpaperGroupSwitcherStyle.chips;
  int _rangeToken = 0;

  bool get initialized => _initialized;

  bool get loading => _loading;

  /// Whether the group data is an unsaved draft.
  bool get draftActive => groupController.draftActive;

  bool get dirty => groupController.dirty;

  /// Groups in display order (group 0 is not a row and is not listed).
  List<WallpaperGroup> get groups => groupController.groups;

  /// The group the wallpaper uses, or `WallpaperGroup.none`.
  WallpaperGroup get current => groupController.current;

  /// The group being viewed; null means group 0.
  String? get selectedGroupId => _selectedGroupId;

  /// The selected group's range, or null for group 0.
  VisibleRange? get range => _range;

  VisibleRangeActiveStyle get activeStyle => _activeStyle;

  WallpaperGroupSwitcherStyle get switcherStyle => _switcherStyle;

  /// A locked range refuses edits, like on the visible-range page.
  bool get canEdit => _range != null && !_range!.locked;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await groupController.init();
      // The page owns the in-memory draft: the first open in a process loads
      // every group and range, and later edits stay here until the user saves.
      await groupController.beginDraft();
      groupController.addListener(_onGroupControllerChanged);
      final db = await _openDb();
      _activeStyle = VisibleRangeActiveStyle.parse((await AppMetaStore(db).read({keyActiveStyle}))[keyActiveStyle]);
      _switcherStyle = WallpaperGroupSwitcherStyle.parse((await AppMetaStore(db).read({keySwitcherStyle}))[keySwitcherStyle]);
      _initialized = true;
      // Resume the group the page showed before it was rebuilt; the first open
      // in a process starts on group 1, since the wallpaper feature itself may
      // never have been visited.
      final session = wallpaperGroupPageSession;
      final sessionId = session.initialized && groups.any((group) => group.id == session.selectedGroupId) ? session.selectedGroupId : null;
      await selectGroup(session.initialized ? sessionId : groups.firstOrNull?.id);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to open the wallpaper group page', error, stack);
      _initialized = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    groupController.removeListener(_onGroupControllerChanged);
    super.dispose();
  }

  /// Re-reads the selected range when the group aggregate changed elsewhere
  /// (a draft edit from the pin sheet, a group rename, discard).
  void _onGroupControllerChanged() {
    final id = _selectedGroupId;
    if (id != null) unawaited(_reloadRange(id));
    notifyListeners();
  }

  Future<void> _reloadRange(String id) async {
    final token = ++_rangeToken;
    final range = await groupController.groupRange(id);
    if (token != _rangeToken || _selectedGroupId != id) return;
    _range = range;
    notifyListeners();
  }

  /// Shows [id]'s range; null selects group 0 (no range to edit).
  Future<void> selectGroup(String? id) async {
    wallpaperGroupPageSession
      ..initialized = true
      ..selectedGroupId = id;
    _selectedGroupId = id;
    _range = null;
    _loading = id != null;
    final token = ++_rangeToken;
    notifyListeners();
    if (id == null) return;
    try {
      final range = await groupController.groupRange(id);
      // The user may have switched again while the range was loading.
      if (token != _rangeToken || _selectedGroupId != id) return;
      _range = range;
    } finally {
      if (token == _rangeToken) _loading = false;
      notifyListeners();
    }
  }

  Future<void> setActiveStyle(VisibleRangeActiveStyle style) async {
    if (_activeStyle == style) return;
    _activeStyle = style;
    notifyListeners();
    await AppMetaStore(await _openDb()).write({keyActiveStyle: style.name});
  }

  Future<void> setSwitcherStyle(WallpaperGroupSwitcherStyle style) async {
    if (_switcherStyle == style) return;
    _switcherStyle = style;
    notifyListeners();
    await AppMetaStore(await _openDb()).write({keySwitcherStyle: style.name});
  }

  Future<void> toggleBaseActive() => _update((range) {
        if (range.baseFilters.isEmpty) return range;
        return range.copyWith(baseActive: !range.baseActive);
      });

  Future<void> setBaseActive(bool active) => _update((range) {
        if (range.baseFilters.isEmpty || range.baseActive == active) return range;
        return range.copyWith(baseActive: active);
      });

  /// Deletes the selected conditions; the base is cleared when [base] is true.
  Future<void> deleteConditions({bool base = false, Set<String> ruleIds = const {}}) => _update((range) {
        if (!base && ruleIds.isEmpty) return range;
        return range.copyWith(
          baseName: base ? '' : range.baseName,
          basePresetId: base ? '' : range.basePresetId,
          baseFilters: base ? const {} : range.baseFilters,
          baseActive: true,
          rules: range.rules.where((rule) => !ruleIds.contains(rule.id)).toList(),
        );
      });

  Future<void> toggleRule(String ruleId) => _update((range) {
        final rule = range.ruleById(ruleId);
        if (rule == null) return range;
        return range.copyWith(
          rules: [
            for (final candidate in range.rules)
              if (candidate.id == ruleId) candidate.copyWith(active: !candidate.active) else candidate,
          ],
        );
      });

  Future<void> renameRule(String ruleId, {required String label, String? description}) => _update((range) {
        return range.copyWith(
          rules: [
            for (final rule in range.rules)
              if (rule.id == ruleId)
                rule.copyWith(
                  label: label.trim().isEmpty ? rule.label : label.trim(),
                  description: description,
                )
              else
                rule,
          ],
        );
      });

  Future<void> deleteRules(Set<String> ids) => _update((range) => range.copyWith(rules: range.rules.where((rule) => !ids.contains(rule.id)).toList()));

  Future<void> setOrder(VisibleRangeOrder order) => _update((range) => range.copyWith(order: order));

  Future<void> lockWithPreset(VisibleRangeLockPreset preset) => _update(
        (range) => range.copyWith(locked: true, permissions: VisibleRangePermissions.of(preset)),
        allowLocked: true,
      );

  Future<void> lock({required VisibleRangePermissions permissions}) => _update(
        (range) => range.copyWith(locked: true, permissions: permissions),
        allowLocked: true,
      );

  Future<void> unlock() => _update((range) => range.copyWith(locked: false), allowLocked: true);

  // group management

  /// Adds a group and opens it, so the user can narrow it right away.
  Future<void> addGroup({String name = '', String description = ''}) async {
    final added = await groupController.addGroup(name: name, description: description);
    await selectGroup(added.id);
  }

  Future<void> updateGroup(String id, {required String name, String? description}) => groupController.updateGroup(id, name: name, description: description);

  /// Deletes a group, moving the page to another one when it was selected.
  Future<bool> deleteGroup(String id) => deleteGroups({id});

  /// Deletes groups, moving the page to another one when the viewed group went.
  ///
  /// The group controller refuses to remove the last group, so the page keeps
  /// something to edit; the boolean is passed on for the "keep one" message.
  Future<bool> deleteGroups(Set<String> ids) async {
    final wasSelected = _selectedGroupId != null && ids.contains(_selectedGroupId);
    final deleted = await groupController.deleteGroups(ids);
    if (!deleted) return false;
    if (wasSelected) {
      await selectGroup(groups.firstOrNull?.id);
    } else {
      notifyListeners();
    }
    return true;
  }

  Future<void> setEnabled(String id, bool enabled) => groupController.setEnabled(id, enabled);

  /// The viewed group's effects, or identity when the group is unknown.
  WallpaperEffectsConfig effectsOf(String id) => groupController.effectsOf(id);

  /// Applies effects immediately, even while the page's range draft is open.
  Future<void> setEffects(String id, WallpaperEffectsConfig effects) => groupController.setEffects(id, effects);

  /// Copies effects to other groups from the "sync to other groups" grid.
  Future<void> setEffectsFor(Set<String> ids, WallpaperEffectsConfig effects) => groupController.setEffectsFor(ids, effects);

  /// Marks [id] as the group the wallpaper uses; null falls back to group 0.
  Future<void> selectCurrent(String? id) => groupController.selectCurrent(id);

  /// Moves a group inside its own segment (enabled or disabled).
  Future<void> moveGroup(String id, int delta) => groupController.moveGroup(id, delta);

  /// Writes the draft to the database in one transaction.
  Future<void> saveDraft() => groupController.saveDraft();

  /// Drops the draft and shows the saved state again.
  Future<void> discardDraft() async {
    final id = _selectedGroupId;
    await groupController.discardDraft();
    await selectGroup(groups.any((group) => group.id == id) ? id : groups.firstOrNull?.id);
  }

  /// Applies [transform] to the selected range and persists it.
  ///
  /// A locked range is read-only, so the guard sits here instead of at every
  /// call site. Locking and unlocking are the only writes a locked range
  /// accepts, otherwise it could never be opened again. The range id is derived
  /// from the group, so the group controller's save guard keeps another group's
  /// range out of this one.
  Future<void> _update(VisibleRange Function(VisibleRange range) transform, {bool allowLocked = false}) async {
    final range = _range;
    if (range == null) return;
    if (range.locked && !allowLocked) return;
    final next = transform(range);
    if (next == range) return;
    _range = next;
    notifyListeners();
    try {
      await groupController.saveGroupRange(next);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to save a wallpaper group range', error, stack);
      // Re-read so the page never shows an unsaved state as saved.
      final id = _selectedGroupId;
      if (id != null) await selectGroup(id);
    }
  }

  Future<AppDatabase> _openDb() async => _db ??= injectedDatabase ?? await getIt<AppDatabaseProvider>().open();
}
