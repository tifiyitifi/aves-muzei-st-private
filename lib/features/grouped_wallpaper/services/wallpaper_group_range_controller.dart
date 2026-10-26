import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/services/wallpaper_group_controller.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart' show VisibleRangeActiveStyle;
import 'package:aves/model/filters/filters.dart';
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

  final WallpaperGroupController groupController;
  final AppDatabase? injectedDatabase;

  new({
    WallpaperGroupController? groupController,
    this.injectedDatabase,
  }) : groupController = groupController ?? WallpaperGroupController();

  AppDatabase? _db;
  bool _initialized = false;
  bool _loading = false;
  String? _selectedGroupId;
  VisibleRange? _range;
  List<VisibleRangePreset> _presets = const [];
  VisibleRangeActiveStyle _activeStyle = VisibleRangeActiveStyle.section;

  bool get initialized => _initialized;

  bool get loading => _loading;

  /// Groups in display order (group 0 is not a row and is not listed).
  List<WallpaperGroup> get groups => groupController.groups;

  /// The group the wallpaper uses, or `WallpaperGroup.none`.
  WallpaperGroup get current => groupController.current;

  /// The group being viewed; null means group 0.
  String? get selectedGroupId => _selectedGroupId;

  /// The selected group's range, or null for group 0.
  VisibleRange? get range => _range;

  List<VisibleRangePreset> get presets => _presets;

  VisibleRangeActiveStyle get activeStyle => _activeStyle;

  /// A locked range refuses edits, like on the visible-range page.
  bool get canEdit => _range != null && !_range!.locked;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await groupController.init();
      groupController.addListener(notifyListeners);
      final db = await _openDb();
      _activeStyle = VisibleRangeActiveStyle.parse((await AppMetaStore(db).read({keyActiveStyle}))[keyActiveStyle]);
      _presets = await VisibleRangeStore(db).loadPresets();
      _initialized = true;
      // Start on the group the wallpaper actually uses, so the page opens on
      // something meaningful; group 0 has nothing to show.
      await selectGroup(current.isNone ? groups.firstOrNull?.id : current.id);
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to open the wallpaper group page', error, stack);
      _initialized = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    groupController.removeListener(notifyListeners);
    super.dispose();
  }

  /// Shows [id]'s range; null selects group 0 (no range to edit).
  Future<void> selectGroup(String? id) async {
    _selectedGroupId = id;
    _range = null;
    _loading = id != null;
    notifyListeners();
    if (id == null) return;
    try {
      final range = await groupController.groupRange(id);
      // The user may have switched again while the range was loading.
      if (_selectedGroupId != id) return;
      _range = range;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setActiveStyle(VisibleRangeActiveStyle style) async {
    if (_activeStyle == style) return;
    _activeStyle = style;
    notifyListeners();
    await AppMetaStore(await _openDb()).write({keyActiveStyle: style.name});
  }

  Future<void> selectBase({required String presetId, required String name, required Set<CollectionFilter> filters}) =>
      _update((range) => range.copyWith(basePresetId: presetId, baseName: name, baseFilters: filters));

  Future<void> clearBase() => _update((range) => range.copyWith(basePresetId: '', baseName: '', baseFilters: const {}));

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
