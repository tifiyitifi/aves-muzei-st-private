import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_condition_pool.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_switcher.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_surface.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_page_session.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart' show VisibleRangeActiveStyle;
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Edits the selected wallpaper group's condition pool for the wallpaper page.
///
/// A group stores its conditions once: the pool is one `wallpaper` range row, and
/// home/lock only mark which conditions they use. The page edits the pool, while
/// the engine, the browsing overlay and the pin sheet consume
/// [projectWallpaperGroupRange] projections of it, so there is exactly one write
/// path and one place that decides what a surface shows.
///
/// The page's own view preferences (the active-style form, the surface being
/// edited) are stored apart from the visible-range page's, so the two pages can
/// look different: a list here and a grid there, for example. The layout itself is
/// already isolated by the page's route key.
class WallpaperGroupRangeController extends ChangeNotifier {
  /// AppMeta key of this page's active-style form.
  static const keyActiveStyle = 'wallpaper.page.activeStyle';

  /// AppMeta key of this page's group switcher style.
  static const keySwitcherStyle = 'wallpaper.page.groupSwitcherStyle';

  /// AppMeta key of the surface the page is editing.
  ///
  /// It is a page preference, not a group setting: reopening the page returns to
  /// the surface the user was last narrowing.
  static const keySurface = 'wallpaper.page.surface';

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
  VisibleRange? _pool;
  WallpaperSurface _surface = WallpaperSurface.home;
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

  /// The group being viewed, or null for group 0.
  WallpaperGroup? get selectedGroup => groups.firstWhereOrNull((group) => group.id == _selectedGroupId);

  /// The surface the editor is showing.
  WallpaperSurface get surface => _surface;

  /// Whether the viewed group has a decoy lock surface.
  bool get separateLockRange => selectedGroup?.separateLockRange ?? false;

  /// The whole condition pool of the viewed group, or null for group 0.
  ///
  /// It holds every condition once, including the ones no surface marks: the page
  /// lists them so they can be switched back on.
  VisibleRange? get pool => _pool;

  /// The viewed surface's projection, or null for group 0.
  VisibleRange? get range => _surface.isLock ? lockRange : homeRange;

  /// The viewed group's home range, whatever surface is active.
  VisibleRange? get homeRange => _project(WallpaperSurface.home);

  /// The viewed group's lock range, or null when the split is off.
  VisibleRange? get lockRange => separateLockRange ? _project(WallpaperSurface.lock) : null;

  VisibleRange? _project(WallpaperSurface surface) {
    final pool = _pool;
    final groupId = _selectedGroupId;
    if (pool == null || groupId == null) return null;
    return projectWallpaperGroupRange(pool, groupId: groupId, surface: surface);
  }

  VisibleRangeActiveStyle get activeStyle => _activeStyle;

  WallpaperGroupSwitcherStyle get switcherStyle => _switcherStyle;

  /// A locked pool refuses edits, like on the visible-range page.
  bool get canEdit {
    final pool = _pool;
    return pool != null && !pool.locked;
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      await groupController.init();
      // The page owns the in-memory draft: the first open in a process loads
      // every group and pool, and later edits stay here until the user saves.
      await groupController.beginDraft();
      groupController.addListener(_onGroupControllerChanged);
      final db = await _openDb();
      _activeStyle = VisibleRangeActiveStyle.parse((await AppMetaStore(db).read({keyActiveStyle}))[keyActiveStyle]);
      _switcherStyle = WallpaperGroupSwitcherStyle.parse((await AppMetaStore(db).read({keySwitcherStyle}))[keySwitcherStyle]);
      _surface = WallpaperSurface.parse((await AppMetaStore(db).read({keySurface}))[keySurface]);
      _initialized = true;
      // Resume the group the page showed before it was rebuilt. The first open
      // in a process starts on group 0 (no browsing constraint); the page may
      // adopt the group the wallpaper is actually running afterwards.
      final session = wallpaperGroupPageSession;
      final sessionId = session.initialized && groups.any((group) => group.id == session.selectedGroupId) ? session.selectedGroupId : null;
      await selectGroup(session.initialized ? sessionId : null);
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

  /// Re-reads the saved groups after another surface moved the current one.
  Future<void> reloadGroups() => groupController.reloadSaved();

  /// Re-reads the selected pool when the group aggregate changed elsewhere
  /// (a draft edit from the pin sheet, a group rename, discard).
  void _onGroupControllerChanged() {
    final id = _selectedGroupId;
    if (id != null) unawaited(_reloadPool(id));
    notifyListeners();
  }

  Future<void> _reloadPool(String id) async {
    final token = ++_rangeToken;
    final pool = await groupController.groupPool(id);
    if (token != _rangeToken || _selectedGroupId != id) return;
    _pool = pool;
    notifyListeners();
  }

  /// Shows [id]'s pool; null selects group 0 (no range to edit).
  Future<void> selectGroup(String? id) async {
    wallpaperGroupPageSession
      ..initialized = true
      ..selectedGroupId = id;
    _selectedGroupId = id;
    _pool = null;
    _loading = id != null;
    final token = ++_rangeToken;
    // A group without a decoy surface has nothing to show on the lock side, so
    // the editor falls back to home instead of displaying an empty section.
    final group = groups.firstWhereOrNull((candidate) => candidate.id == id);
    if (_surface.isLock && group?.separateLockRange != true) await _setSurface(WallpaperSurface.home);
    notifyListeners();
    if (id == null) return;
    try {
      final pool = await groupController.groupPool(id);
      // The user may have switched again while the pool was loading.
      if (token != _rangeToken || _selectedGroupId != id) return;
      _pool = pool;
    } finally {
      if (token == _rangeToken) _loading = false;
      notifyListeners();
    }
  }

  /// Switches the range editor between the home and lock surfaces.
  Future<void> switchSurface(WallpaperSurface surface) async {
    if (_surface == surface) return;
    if (surface.isLock && !separateLockRange) return;
    await _setSurface(surface);
    notifyListeners();
  }

  /// Turns the viewed group's decoy lock surface on or off.
  ///
  /// Enabling seeds the lock marks once from the home ones, so the two start
  /// identical and then narrow independently; disabling only hides the lock
  /// marks, so re-enabling reuses the narrowing the user already made.
  Future<void> setSeparateLockRange(bool enabled) async {
    final id = _selectedGroupId;
    if (id == null) return;
    await groupController.setSeparateLockRange(id, enabled);
    if (!enabled && _surface.isLock) await _setSurface(WallpaperSurface.home);
    await _reloadPool(id);
    notifyListeners();
  }

  Future<void> _setSurface(WallpaperSurface surface) async {
    _surface = surface;
    await AppMetaStore(await _openDb()).write({keySurface: surface.name});
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

  // conditions

  /// Adds or removes [surface]'s mark on one rule.
  Future<void> toggleRuleSurface(String ruleId, WallpaperSurface surface) => _updatePool((pool) {
    final rule = pool.ruleById(ruleId);
    if (rule == null) return pool;
    final enabled = !WallpaperConditionSurfaces.contains(rule.surfaces, surface);
    return pool.copyWith(
      rules: [
        for (final candidate in pool.rules) candidate.id == ruleId ? candidate.copyWith(surfaces: WallpaperConditionSurfaces.withSurface(candidate.surfaces, surface, enabled)) : candidate,
      ],
    );
  });

  /// Marks or clears the group's base on one surface.
  ///
  /// A surface uses at most one base, so this is a single switch: clearing it
  /// keeps the filters in the pool for the other surface or for later.
  Future<void> setBaseSurface(WallpaperSurface surface, bool enabled) => _updatePool((pool) {
    if (enabled && pool.baseFilters.isEmpty) return pool;
    if (WallpaperConditionSurfaces.contains(pool.baseSurfaces, surface) == enabled) return pool;
    return pool.copyWith(baseSurfaces: WallpaperConditionSurfaces.withSurface(pool.baseSurfaces, surface, enabled));
  });

  /// Deletes the given conditions from the pool: both surfaces lose them.
  ///
  /// Unmarking one surface is [toggleRuleSurface]; this is the explicit "this
  /// condition is gone" action.
  Future<void> deleteConditions({bool base = false, Set<String> ruleIds = const {}}) => _updatePool((pool) {
    if (!base && ruleIds.isEmpty) return pool;
    return pool.copyWith(
      baseName: base ? '' : pool.baseName,
      basePresetId: base ? '' : pool.basePresetId,
      baseFilters: base ? const {} : pool.baseFilters,
      baseSurfaces: base ? 0 : pool.baseSurfaces,
      rules: pool.rules.where((rule) => !ruleIds.contains(rule.id)).toList(),
    );
  });

  Future<void> renameRule(String ruleId, {required String label, String? description}) => _updatePool((pool) {
    return pool.copyWith(
      rules: [
        for (final rule in pool.rules)
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

  Future<void> deleteRules(Set<String> ids) => _updatePool((pool) => pool.copyWith(rules: pool.rules.where((rule) => !ids.contains(rule.id)).toList()));

  /// Replaces one rule with [rule], keeping it in the pool.
  Future<void> updateRule(VisibleRangeRule rule) => _updatePool((pool) {
    if (pool.ruleById(rule.id) == null) return pool;
    return pool.copyWith(rules: [for (final candidate in pool.rules) candidate.id == rule.id ? rule : candidate]);
  });

  /// Moves a rule to another section, appended after the rules already there.
  Future<void> moveRuleToKind(String ruleId, VisibleRangeRuleKind kind) => _updatePool((pool) {
    final rule = pool.ruleById(ruleId);
    if (rule == null || rule.kind == kind) return pool;
    final moved = rule.copyWith(kind: kind, position: pool.rulesOf(kind).length);
    return pool.copyWith(rules: [for (final candidate in pool.rules) candidate.id == ruleId ? moved : candidate]);
  });

  /// Turns a rule into the group's base and removes the rule.
  ///
  /// The base is one slot shared by both surfaces, exactly like a rule: it takes
  /// the rule's filters and the surfaces the rule was marked for.
  Future<void> moveRuleToBase(String ruleId, {required String name}) => _updatePool((pool) {
    final rule = pool.ruleById(ruleId);
    if (rule == null) return pool;
    return pool.copyWith(
      baseName: name.trim(),
      basePresetId: '',
      baseFilters: rule.filters,
      baseSurfaces: rule.surfaces,
      rules: pool.rules.where((candidate) => candidate.id != ruleId).toList(),
    );
  });

  Future<void> setOrder(VisibleRangeOrder order) => _updatePool((pool) => pool.copyWith(order: order));

  Future<void> lockWithPreset(VisibleRangeLockPreset preset) => _updatePool(
    (pool) => pool.copyWith(locked: true, permissions: VisibleRangePermissions.of(preset)),
    allowLocked: true,
  );

  Future<void> lock({required VisibleRangePermissions permissions}) => _updatePool(
    (pool) => pool.copyWith(locked: true, permissions: permissions),
    allowLocked: true,
  );

  Future<void> unlock() => _updatePool((pool) => pool.copyWith(locked: false), allowLocked: true);

  // group management

  /// Adds a group and opens it, so the user can narrow it right away.
  Future<void> addGroup({String name = '', String description = ''}) async {
    final added = await groupController.addGroup(name: name, description: description);
    await selectGroup(added.id);
  }

  Future<void> updateGroup(String id, {required String name, String? description}) => groupController.updateGroup(id, name: name, description: description);

  /// Copies [id] into a new group and opens the copy.
  ///
  /// Returns null when the group is unknown or locked, so the page can explain
  /// why nothing happened instead of silently doing nothing.
  Future<WallpaperGroup?> duplicateGroup(String id, {required String name}) async {
    final copy = await groupController.duplicateGroup(id, name: name);
    if (copy == null) return null;
    await selectGroup(copy.id);
    return copy;
  }

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

  /// Applies effects immediately, even while the page's pool draft is open.
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

  /// Applies [transform] to the condition pool and persists it.
  ///
  /// A locked pool is read-only, so the guard sits here instead of at every call
  /// site. Locking and unlocking are the only writes a locked pool accepts,
  /// otherwise it could never be opened again.
  Future<void> _updatePool(VisibleRange Function(VisibleRange pool) transform, {bool allowLocked = false}) async {
    final pool = _pool;
    if (pool == null) return;
    if (pool.locked && !allowLocked) return;
    final next = transform(pool);
    if (next == pool) return;
    _pool = next;
    notifyListeners();
    try {
      _pool = await groupController.saveGroupPool(next);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to save a wallpaper group pool', error, stack);
      // Re-read so the page never shows an unsaved state as saved.
      final id = _selectedGroupId;
      if (id != null) await selectGroup(id);
    }
  }

  Future<AppDatabase> _openDb() async => _db ??= injectedDatabase ?? await getIt<AppDatabaseProvider>().open();
}
