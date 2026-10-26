import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_layout.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Loads the bundled group defaults; injectable so tests never read assets.
typedef WallpaperGroupDefaultLoader = Future<List<WallpaperGroupDefinition>> Function();

/// Owns the wallpaper group list and each group's visible range.
///
/// The groups are one aggregate: order, numbering, the enabled segments and the
/// single current group are always normalized together, so no caller has to know
/// the invariant rules. Group 0 is [WallpaperGroup.none], never a row.
///
/// Nothing here talks to the live wallpaper: baking, notifications and
/// `isActive` arbitration belong to the engine phase.
class WallpaperGroupController extends ChangeNotifier {
  /// Version of the bundled defaults last applied, mirroring the visible-range
  /// seeding. A bump re-applies the bundle order and prunes built-in groups that
  /// no longer ship, while a renamed or narrowed group keeps what the user made
  /// of it.
  static const defaultsVersion = 1;

  /// Prefix of the built-in group ids, so a bundle bump can tell them apart from
  /// the user's own groups.
  static const bundledGroupIdPrefix = 'wallpaper.group.';

  final AppDatabase? injectedDatabase;
  final WallpaperGroupDefaultLoader defaultLoader;

  /// Whether [defaultLoader] reads the bundled asset. Only bundled defaults need
  /// the device's standard directories, so only they wait for storage to be
  /// ready instead of being seeded closed.
  final bool _usesBundledDefaults;

  /// Loads the bundled restriction/supplement candidates reused per group;
  /// injectable so tests need no asset bundle.
  final Future<List<VisibleRangePresetDefinition>> Function() ruleLoader;

  new({
    this.injectedDatabase,
    WallpaperGroupDefaultLoader? defaultLoader,
    Future<List<VisibleRangePresetDefinition>> Function()? ruleLoader,
  })  : _usesBundledDefaults = defaultLoader == null,
        defaultLoader = defaultLoader ?? _loadBundledDefaults,
        ruleLoader = ruleLoader ?? loadVisibleRangePresetDefinitions;

  static Future<List<WallpaperGroupDefinition>> _loadBundledDefaults() => loadWallpaperGroupDefinitions();

  AppDatabase? _db;
  WallpaperGroupStore? _store;
  List<WallpaperGroup> _groups = const [];
  Future<void>? _initFuture;
  bool _initialized = false;
  int _idSequence = 0;

  bool get initialized => _initialized;

  /// Groups in display order; numbers are `1..n`, enabled groups first.
  List<WallpaperGroup> get groups => _groups;

  List<WallpaperGroup> get enabledGroups => enabledWallpaperGroups(_groups);

  /// The group the wallpaper uses, or [WallpaperGroup.none] (group 0).
  WallpaperGroup get current => _groups.firstWhereOrNull((group) => group.current && group.enabled) ?? WallpaperGroup.none;

  Future<void> init() {
    if (_initialized) return Future.value();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      final store = await _openStore();
      var groups = normalizeWallpaperGroups(await store.loadGroups());
      final storedVersion = await store.readDefaultsVersion();
      if (groups.isEmpty || storedVersion < defaultsVersion) {
        // An unreadable bundle must not burn the version marker: the next start
        // with a readable asset still has to seed.
        groups = await _applyDefaults(store, groups) ?? groups;
      }
      _groups = groups;
    } catch (error, stack) {
      // A broken group store must not block the app: the page simply shows no
      // group, and the wallpaper keeps whatever it already baked.
      groupedWallpaperLog.e('failed to load wallpaper groups', error, stack);
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Applies the bundled groups, returning the resulting list or null when the
  /// bundle could not be read.
  ///
  /// Built-ins already stored are kept as-is, so a rename, a disabled switch and
  /// the activation inside a group's range survive a defaults bump. A built-in
  /// the bundle dropped is deleted together with its range.
  Future<List<WallpaperGroup>?> _applyDefaults(WallpaperGroupStore store, List<WallpaperGroup> groups) async {
    if (_usesBundledDefaults) {
      try {
        await _ensureStandardPaths();
      } catch (error, stack) {
        // Seeding now would resolve no folder and close every group (a privacy
        // default fails closed), which is wrong while the device is still
        // booting. Leave the list as it is and retry on the next open.
        groupedWallpaperLog.e('failed to resolve standard paths, deferring the group defaults', error, stack);
        return null;
      }
    }
    final definitions = await defaultLoader();
    if (definitions.isEmpty) return null;
    final ruleCandidates = await _loadRuleCandidates();

    final now = DateTime.now().millisecondsSinceEpoch;
    final ranges = VisibleRangeStore(store.db);
    final byId = {for (final group in groups) group.id: group};
    final bundledIds = definitions.map((definition) => definition.id).toSet();
    final next = <WallpaperGroup>[];
    for (final definition in definitions) {
      final existing = byId[definition.id];
      if (existing != null) {
        next.add(existing);
        continue;
      }
      next.add(
        WallpaperGroup(
          id: definition.id,
          name: '@${definition.nameKey}',
          enabled: definition.enabled,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await ranges.saveRange(
        VisibleRange(
          id: wallpaperGroupRangeId(definition.id),
          scope: VisibleRangeScope.wallpaper,
          ownerId: definition.id,
          // A base name is only shown when the base is not 「unrestricted」.
          baseName: definition.filters.isEmpty ? '' : '@${definition.nameKey}',
          baseFilters: definition.filters,
          rules: _bundledRules(definition.id, ruleCandidates),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    // The user's own groups keep their relative order, after the bundled ones.
    next.addAll(groups.where((group) => !bundledIds.contains(group.id)));
    for (final dropped in groups.where((group) => _isBundledGroup(group.id) && !bundledIds.contains(group.id))) {
      await store.deleteGroup(dropped.id);
    }

    final restored = _applyBundledCurrent(normalizeWallpaperGroups(next), definitions);
    await store.saveGroups(restored);
    await store.writeDefaultsVersion(defaultsVersion);
    return restored;
  }

  /// Gives the bundle's declared current group the flag when nothing is current.
  List<WallpaperGroup> _applyBundledCurrent(List<WallpaperGroup> groups, List<WallpaperGroupDefinition> definitions) {
    if (groups.any((group) => group.current && group.enabled)) return groups;
    final wanted = definitions.firstWhereOrNull((definition) => definition.current)?.id;
    if (wanted == null) return groups;
    return normalizeWallpaperGroups([
      for (final group in groups) group.copyWith(current: group.id == wanted),
    ]);
  }

  static bool _isBundledGroup(String id) => id.startsWith(bundledGroupIdPrefix);

  /// The bundled restriction/supplement candidates, reused for every group.
  ///
  /// A wallpaper group narrows like the gallery does, so its page offers the
  /// same vocabulary instead of an empty restrictions/supplements section. All
  /// of them start switched off. A candidate whose folder cannot be resolved is
  /// skipped by the asset parser, which is the same fail-closed rule the gallery
  /// applies.
  Future<List<VisibleRangePresetDefinition>> _loadRuleCandidates() async {
    try {
      final definitions = await ruleLoader();
      return definitions.where((definition) => definition.kind != VisibleRangePresetKind.base).toList();
    } catch (error, stack) {
      groupedWallpaperLog.e('failed to load the bundled rule candidates, seeding bare groups', error, stack);
      return const [];
    }
  }

  /// Materializes the bundled rules for one group, all inactive.
  ///
  /// Rule ids are global, so the same candidate gets a per-group id; position is
  /// per kind, matching the gallery's ordering.
  List<VisibleRangeRule> _bundledRules(String groupId, List<VisibleRangePresetDefinition> candidates) {
    final rangeId = wallpaperGroupRangeId(groupId);
    final restriction = candidates.where((definition) => definition.kind == VisibleRangePresetKind.restriction).toList();
    final supplement = candidates.where((definition) => definition.kind == VisibleRangePresetKind.supplement).toList();
    return [
      for (var i = 0; i < restriction.length; i++)
        _bundledRule(groupId, rangeId, restriction[i], VisibleRangeRuleKind.restriction, i),
      for (var i = 0; i < supplement.length; i++)
        _bundledRule(groupId, rangeId, supplement[i], VisibleRangeRuleKind.supplement, i),
    ];
  }

  static VisibleRangeRule _bundledRule(String groupId, String rangeId, VisibleRangePresetDefinition definition, VisibleRangeRuleKind kind, int position) => VisibleRangeRule(
        id: wallpaperGroupRuleId(groupId, definition.id),
        rangeId: rangeId,
        kind: kind,
        position: position,
        // `@` marks an ARB key, like the gallery's own default rules.
        label: '@${definition.nameKey}',
        filters: definition.filters,
        active: false,
      );

  /// Makes the standard directories available before the asset is resolved.
  ///
  /// `androidFileUtils.init` runs after the first frame otherwise. A device that
  /// is still booting reports no storage volume: skip the seed instead of
  /// blocking the first frame on its retry loop, and try again next time.
  Future<void> _ensureStandardPaths() async {
    try {
      androidFileUtils.dcimPath;
      return;
    } catch (_) {
      // Not initialized yet.
    }
    if (androidFileUtils.storageVolumes.isEmpty) {
      final volumes = await storageService.getStorageVolumes();
      if (volumes.isEmpty) throw StateError('storage volumes are not ready');
    }
    await androidFileUtils.init();
  }

  /// Adds a group at the end of the enabled segment.
  ///
  /// A new group starts unrestricted: the user just created it, so showing every
  /// image until they narrow it is the expected behaviour. Failing closed only
  /// applies to a bundled group whose folder could not be resolved.
  Future<void> addGroup({String name = ''}) async {
    _requireInitialized();
    final store = await _openStore();
    final now = _now;
    final group = WallpaperGroup(
      id: 'group.$now.${_idSequence++}',
      name: name.trim(),
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
    await _commit(store, [..._groups, group]);
  }

  Future<void> renameGroup(String id, String name) async {
    _requireInitialized();
    final trimmed = name.trim();
    final group = _groups.firstWhereOrNull((candidate) => candidate.id == id);
    if (group == null || trimmed.isEmpty || group.name == trimmed) return;
    final store = await _openStore();
    await _commit(store, [
      for (final candidate in _groups)
        if (candidate.id == id) candidate.copyWith(name: trimmed, updatedAt: _now) else candidate,
    ]);
  }

  /// Deletes a group and its range.
  ///
  /// Refuses to remove the last group: the page and the notification need one
  /// concrete group to fall back to, even when every group is disabled.
  Future<bool> deleteGroup(String id) async {
    _requireInitialized();
    if (_groups.length <= 1 || !_groups.any((group) => group.id == id)) return false;
    final store = await _openStore();
    await store.deleteGroup(id);
    await _commit(store, _groups.where((group) => group.id != id).toList());
    return true;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _requireInitialized();
    final next = setWallpaperGroupEnabled(_groups, id, enabled);
    if (listEquals(next, _groups)) return;
    await _commit(await _openStore(), next);
  }

  Future<void> moveGroup(String id, int delta) async {
    _requireInitialized();
    final next = moveWallpaperGroup(_groups, id, delta);
    if (listEquals(next, _groups)) return;
    await _commit(await _openStore(), next);
  }

  /// Makes [id] the current group, or group 0 when null.
  Future<void> selectCurrent(String? id) async {
    _requireInitialized();
    if (id != null && !_groups.any((group) => group.id == id && group.enabled)) return;
    final next = normalizeWallpaperGroups([
      for (final group in _groups) group.copyWith(current: id != null && group.id == id),
    ]);
    if (listEquals(next, _groups)) return;
    await _commit(await _openStore(), next);
  }

  /// The group's visible range, or a fresh unrestricted one when it has none.
  Future<VisibleRange> groupRange(String groupId) async {
    final store = await _openStore();
    final existing = await VisibleRangeStore(store.db).loadRange(scope: VisibleRangeScope.wallpaper, ownerId: groupId);
    if (existing != null) return existing;
    return VisibleRange(
      id: wallpaperGroupRangeId(groupId),
      scope: VisibleRangeScope.wallpaper,
      ownerId: groupId,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  /// Saves a group's range after checking it really belongs to that group.
  ///
  /// The id is derived from the owner, so a caller cannot write a range under
  /// another group by mistake.
  Future<void> saveGroupRange(VisibleRange range) async {
    _requireInitialized();
    if (range.scope != VisibleRangeScope.wallpaper) {
      throw ArgumentError.value(range.scope, 'range.scope', 'only wallpaper ranges are accepted');
    }
    if (range.id != wallpaperGroupRangeId(range.ownerId)) {
      throw ArgumentError.value(range.id, 'range.id', 'the range id must be derived from the group id');
    }
    if (!_groups.any((group) => group.id == range.ownerId)) {
      throw ArgumentError.value(range.ownerId, 'range.ownerId', 'unknown wallpaper group');
    }
    final store = await _openStore();
    final now = _now;
    await VisibleRangeStore(store.db).saveRange(range.copyWith(updatedAt: now));
    _groups = [
      for (final group in _groups)
        if (group.id == range.ownerId) group.copyWith(updatedAt: now) else group,
    ];
    await store.saveGroups(_groups);
    notifyListeners();
  }

  Future<void> _commit(WallpaperGroupStore store, List<WallpaperGroup> groups) async {
    _groups = normalizeWallpaperGroups(groups);
    await store.saveGroups(_groups);
    notifyListeners();
  }

  Future<WallpaperGroupStore> _openStore() async {
    final existing = _store;
    if (existing != null) return existing;
    final db = _db ??= injectedDatabase ?? await getIt<AppDatabaseProvider>().open();
    return _store = WallpaperGroupStore(db);
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('WallpaperGroupController is not initialized');
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;
}
