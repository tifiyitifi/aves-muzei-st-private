import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/grouped_wallpaper/data/default_groups.dart';
import 'package:aves/features/grouped_wallpaper/db/wallpaper_group_store.dart';
import 'package:aves/features/grouped_wallpaper/log.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group.dart';
import 'package:aves/features/grouped_wallpaper/model/wallpaper_group_layout.dart';
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
  /// seeding. A bump re-applies the bundle order, prunes built-in groups that no
  /// longer ship and removes the restriction/supplement candidates older
  /// versions materialized into every group, while a renamed or narrowed group
  /// keeps what the user made of it.
  static const defaultsVersion = 2;

  /// Prefix of the built-in group ids, so a bundle bump can tell them apart from
  /// the user's own groups.
  static const bundledGroupIdPrefix = 'wallpaper.group.';

  final AppDatabase? injectedDatabase;
  final WallpaperGroupDefaultLoader defaultLoader;

  /// Whether [defaultLoader] reads the bundled asset. Only bundled defaults need
  /// the device's standard directories, so only they wait for storage to be
  /// ready instead of being seeded closed.
  final bool _usesBundledDefaults;

  new({
    this.injectedDatabase,
    WallpaperGroupDefaultLoader? defaultLoader,
  })  : _usesBundledDefaults = defaultLoader == null,
        defaultLoader = defaultLoader ?? _loadBundledDefaults;

  static Future<List<WallpaperGroupDefinition>> _loadBundledDefaults() => loadWallpaperGroupDefinitions();

  AppDatabase? _db;
  WallpaperGroupStore? _store;
  List<WallpaperGroup> _groups = const [];
  Future<void>? _initFuture;
  bool _initialized = false;
  int _idSequence = 0;

  /// Whether the wallpaper page's in-memory draft owns the groups and ranges.
  ///
  /// The page starts the draft on its first open in a process: from then on all
  /// group edits stay in memory until [saveDraft], so the user can preview
  /// changes without touching the state the live wallpaper uses. Before the
  /// page is ever opened, edits persist immediately (the pin sheet can target a
  /// group without the page).
  bool _draftActive = false;
  bool _dirty = false;
  final Map<String, VisibleRange> _ranges = {};
  final Set<String> _deletedIds = {};

  bool get initialized => _initialized;

  bool get draftActive => _draftActive;

  /// Whether the draft differs from what is saved in the database.
  bool get dirty => _dirty;

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
    // A wallpaper group starts with its one exclusive base and nothing else:
    // the gallery's restriction/supplement catalogue is not copied here. Older
    // versions materialized it, so the bump removes those seeded rules while a
    // rule the user switched on or renamed stays.
    await _pruneSeededRules(ranges, next);

    final restored = _applyBundledCurrent(normalizeWallpaperGroups(next), definitions);
    await store.saveGroups(restored);
    await store.writeDefaultsVersion(defaultsVersion);
    return restored;
  }

  /// Drops the rule candidates an older defaults version seeded into a group.
  ///
  /// Only rules that are still switched off and still carry their bundled `@`
  /// label go: an activation or a rename is the user's decision and outlives the
  /// bundle. Ids are prefixed with the group id, so a user rule is never caught.
  static Future<void> _pruneSeededRules(VisibleRangeStore ranges, Iterable<WallpaperGroup> groups) async {
    for (final group in groups) {
      final range = await ranges.loadRange(scope: VisibleRangeScope.wallpaper, ownerId: group.id);
      if (range == null) continue;
      final prefix = '${group.id}.rule.';
      final kept = [
        for (final rule in range.rules)
          if (!(rule.id.startsWith(prefix) && !rule.active && rule.label.startsWith('@'))) rule,
      ];
      if (kept.length != range.rules.length) {
        await ranges.saveRange(range.copyWith(rules: kept));
      }
    }
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

  /// Starts (or keeps) the wallpaper page's in-memory draft.
  ///
  /// Called on the page's first open in a process, not at startup: the wallpaper
  /// feature may never be visited. Loading all ranges here means the page can
  /// switch groups and toggle conditions without hitting the database, and the
  /// saved state keeps serving the live wallpaper until [saveDraft].
  Future<void> beginDraft() async {
    await init();
    if (_draftActive) return;
    final store = await _openStore();
    await _loadDraftRanges(store);
    _deletedIds.clear();
    _draftActive = true;
    _dirty = false;
    notifyListeners();
  }

  Future<void> _loadDraftRanges(WallpaperGroupStore store) async {
    final ranges = VisibleRangeStore(store.db);
    _ranges.clear();
    for (final group in _groups) {
      final range = await ranges.loadRange(scope: VisibleRangeScope.wallpaper, ownerId: group.id);
      if (range != null) _ranges[group.id] = range;
    }
  }

  /// Writes the draft back in one transaction: removed groups and their ranges
  /// first, then the group list, then every edited range.
  Future<void> saveDraft() async {
    if (!_draftActive) return;
    final store = await _openStore();
    final ranges = VisibleRangeStore(store.db);
    await store.db.transaction(() async {
      for (final id in _deletedIds) {
        await store.deleteGroup(id);
      }
      await store.saveGroups(_groups);
      for (final group in _groups) {
        final range = _ranges[group.id];
        if (range != null) await ranges.saveRange(range);
      }
    });
    _deletedIds.clear();
    _dirty = false;
    notifyListeners();
  }

  /// Drops the draft and reloads the saved state.
  Future<void> discardDraft() async {
    if (!_draftActive) return;
    final store = await _openStore();
    _groups = normalizeWallpaperGroups(await store.loadGroups());
    await _loadDraftRanges(store);
    _deletedIds.clear();
    _dirty = false;
    notifyListeners();
  }

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

  /// The stored range with [rangeId], or null when it belongs to no group.
  ///
  /// The pin sheet and the write-back list address a range by id, while a group
  /// owns exactly one derived range id, so this is the reverse lookup.
  Future<VisibleRange?> loadRangeById(String rangeId) async {
    final group = _groups.firstWhereOrNull((group) => wallpaperGroupRangeId(group.id) == rangeId);
    if (group == null) return null;
    return groupRange(group.id);
  }

  /// Adds a group at the end of the enabled segment.
  ///
  /// A new group starts unrestricted: the user just created it, so showing every
  /// image until they narrow it is the expected behaviour. Failing closed only
  /// applies to a bundled group whose folder could not be resolved.
  Future<WallpaperGroup> addGroup({String name = '', String description = ''}) async {
    _requireInitialized();
    final now = _now;
    final group = WallpaperGroup(
      id: 'group.$now.${_idSequence++}',
      name: name.trim(),
      description: description.trim(),
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
    await _writeGroups([..._groups, group]);
    return _groups.firstWhere((candidate) => candidate.id == group.id);
  }

  /// Updates the user text of a group. An empty name keeps the current one, so
  /// the dialog cannot leave a group nameless.
  Future<void> updateGroup(String id, {required String name, String? description}) async {
    _requireInitialized();
    final trimmed = name.trim();
    final nextDescription = description?.trim();
    final group = _groups.firstWhereOrNull((candidate) => candidate.id == id);
    if (group == null) return;
    final nextName = trimmed.isEmpty ? group.name : trimmed;
    final resolvedDescription = nextDescription ?? group.description;
    if (group.name == nextName && group.description == resolvedDescription) return;
    await _writeGroups([
      for (final candidate in _groups)
        if (candidate.id == id) candidate.copyWith(name: nextName, description: resolvedDescription, updatedAt: _now) else candidate,
    ]);
  }

  /// Deletes a group together with its visible range.
  ///
  /// Refuses to remove the last group: the page and the notification need one
  /// concrete group to fall back to, even when every group is disabled.
  Future<bool> deleteGroup(String id) async {
    _requireInitialized();
    if (_groups.length <= 1 || !_groups.any((group) => group.id == id)) return false;
    final remaining = _groups.where((group) => group.id != id).toList();
    if (_draftActive) {
      _groups = normalizeWallpaperGroups(remaining);
      _ranges.remove(id);
      _deletedIds.add(id);
      _dirty = true;
      notifyListeners();
      return true;
    }
    final store = await _openStore();
    await store.deleteGroup(id);
    _groups = normalizeWallpaperGroups(remaining);
    await store.saveGroups(_groups);
    notifyListeners();
    return true;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _requireInitialized();
    final next = setWallpaperGroupEnabled(_groups, id, enabled);
    if (listEquals(next, _groups)) return;
    await _writeGroups(next);
  }

  Future<void> moveGroup(String id, int delta) async {
    _requireInitialized();
    final next = moveWallpaperGroup(_groups, id, delta);
    if (listEquals(next, _groups)) return;
    await _writeGroups(next);
  }

  /// Makes [id] the current group, or group 0 when null.
  Future<void> selectCurrent(String? id) async {
    _requireInitialized();
    if (id != null && !_groups.any((group) => group.id == id && group.enabled)) return;
    final next = normalizeWallpaperGroups([
      for (final group in _groups) group.copyWith(current: id != null && group.id == id),
    ]);
    if (listEquals(next, _groups)) return;
    await _writeGroups(next);
  }

  /// The group's visible range, or a fresh unrestricted one when it has none.
  Future<VisibleRange> groupRange(String groupId) async {
    if (_draftActive) {
      final cached = _ranges[groupId];
      if (cached != null) return cached;
      return VisibleRange(
        id: wallpaperGroupRangeId(groupId),
        scope: VisibleRangeScope.wallpaper,
        ownerId: groupId,
        createdAt: _now,
        updatedAt: _now,
      );
    }
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
  /// another group by mistake. While the draft is active this only updates the
  /// in-memory range; [saveDraft] is what touches the database.
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
    final now = _now;
    final next = range.copyWith(updatedAt: now);
    if (_draftActive) {
      _ranges[range.ownerId] = next;
      _groups = [
        for (final group in _groups)
          if (group.id == range.ownerId) group.copyWith(updatedAt: now) else group,
      ];
      _dirty = true;
      notifyListeners();
      return;
    }
    final store = await _openStore();
    await VisibleRangeStore(store.db).saveRange(next);
    _groups = [
      for (final group in _groups)
        if (group.id == range.ownerId) group.copyWith(updatedAt: now) else group,
    ];
    await store.saveGroups(_groups);
    notifyListeners();
  }

  /// Updates the group list in memory (draft) or in the database.
  Future<void> _writeGroups(List<WallpaperGroup> groups) async {
    final next = normalizeWallpaperGroups(groups);
    if (_draftActive) {
      _groups = next;
      _dirty = true;
      notifyListeners();
      return;
    }
    final store = await _openStore();
    _groups = next;
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

/// The app-wide group controller (the same singleton style as
/// `visibleRangeController`).
///
/// The pin sheet, the write-back list and, later, the wallpaper engine read the
/// groups without a page being open, so the list has one owner for the whole
/// process. The page keeps only its scoped range editor.
final WallpaperGroupController wallpaperGroupController = WallpaperGroupController();
