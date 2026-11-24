import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
import 'package:aves/features/visible_range/model/visible_range_pin_split.dart';
import 'package:aves/features/visible_range/model/visible_range_usage.dart';
import 'package:aves/features/visible_range/model/visible_range_write_back.dart';
import 'package:aves/features/visible_range/services/visible_range_target_source.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/utils/android_file_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

const String visibleRangeLogKey = 'log.visible_range';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> visibleRangeDebugLogKeys = [visibleRangeLogKey];

const AreaKeyLog _log = AreaKeyLog(visibleRangeLogKey);

/// How the "current visible range" is presented.
enum VisibleRangeActiveStyle {
  /// Default: the active conditions repeat as a grid section, sharing the
  /// layout, tile size and pinch zoom of the three candidate groups.
  section,
  compactChips,
  tiles;

  static VisibleRangeActiveStyle parse(String? value) {
    for (final style in values) {
      if (style.name == value) return style;
    }
    return section;
  }
}

/// The single source of truth for visibility groups.
///
/// It is a `ChangeNotifier` rather than a provider-held notifier because the
/// current range is consulted from synchronous, non-widget seams (the collection
/// source and the paged engine router). Widgets subscribe through
/// `context.watch`/`AnimatedBuilder`, and the collection surfaces refresh on
/// [notifyListeners] instead of polling.
///
/// The gallery owns N mutually exclusive groups plus one scope-wide outside pool;
/// the wallpaper groups own one pool each and are reached through [targetSource].
/// A gallery lock freezes the whole gallery configuration, not one group: the
/// current group cannot change and no condition, group or outside rule can be
/// written until the PIN unlocks it.
class VisibleRangeController extends ChangeNotifier {
  /// Optional injected database, used by tests (which never register the
  /// app-wide [AppDatabaseProvider]).
  final AppDatabase? injectedDatabase;

  /// Loads the bundled preset definitions. Injectable so tests need no asset
  /// bundle.
  final Future<List<VisibleRangePresetDefinition>> Function() presetLoader;

  /// Whether [presetLoader] is the bundled asset loader. Only the bundled
  /// defaults need the device's standard directories, so only they wait for
  /// storage volumes to be ready.
  final bool _usesBundledDefaults;

  new({this.injectedDatabase, Future<List<VisibleRangePresetDefinition>> Function()? presetLoader})
    : _usesBundledDefaults = presetLoader == null,
      presetLoader = presetLoader ?? _loadBundledPresets;

  static Future<List<VisibleRangePresetDefinition>> _loadBundledPresets() => loadVisibleRangePresetDefinitions();

  VisibleRangeStore? _store;
  List<VisibleRange> _galleryGroups = const [];
  String _currentGalleryGroupId = VisibleRange.galleryRangeId;
  VisibleRange _galleryOutside = VisibleRange.emptyOutside();
  List<VisibleRangePreset> _presets = const [];
  VisibleRangeLockPreset _lastLockPreset = VisibleRangeLockPreset.readOnly;
  VisibleRangeActiveStyle _activeStyle = VisibleRangeActiveStyle.section;
  VisibleRangeInjectionMode _pinInjectionMode = VisibleRangeInjectionMode.auto;
  bool _pinInjectionRemembered = false;
  Future<void>? _initFuture;
  bool _initialized = false;
  int _idCounter = 0;

  bool get initialized => _initialized;

  /// The group browsing uses.
  VisibleRange get gallery => _galleryGroups.firstWhereOrNull((group) => group.id == _currentGalleryGroupId) ?? _galleryGroups.firstOrNull ?? VisibleRange.emptyGallery();

  /// Every gallery group, in display order.
  List<VisibleRange> get galleryGroups => _galleryGroups;

  String get currentGalleryGroupId => gallery.id;

  /// The scope-wide pool shared by every gallery group.
  VisibleRange get outside => _galleryOutside;

  /// The gallery group at [id], or null when it is unknown.
  VisibleRange? galleryGroupById(String id) => _galleryGroups.firstWhereOrNull((group) => group.id == id);

  /// The 1-based number shown on a group badge.
  ///
  /// Group 0 is the 「Unrestricted」 sentinel: it is listed but never numbered as
  /// a data group, so the first real group is 1, matching the wallpaper page's
  /// group 0 = "no group".
  int galleryGroupNumber(String id) {
    if (isGroupZero(id)) return 0;
    final dataGroups = _galleryGroups.where((group) => !isGroupZero(group.id)).toList();
    return dataGroups.indexWhere((group) => group.id == id) + 1;
  }

  /// Whether [id] is the gallery's unrestricted sentinel group.
  ///
  /// Group 0 holds no conditions: it is the state browsing starts in, not a
  /// container. Every condition write refuses it, and no save target lists it.
  bool isGroupZero(String id) => id == VisibleRange.galleryRangeId;

  /// Whether the current group accepts condition edits.
  bool get canEditCurrentGroup => canEdit && !isGroupZero(gallery.id);

  /// Whether [id] accepts condition edits.
  bool canEditGroup(String id) => canEdit && !isGroupZero(id);

  /// The legacy template catalog. Groups are the editable form now; the rows are
  /// kept one release so a rollback can still read them.
  List<VisibleRangePreset> get presets => _presets;

  /// The filter resolved from the current group plus the outside pool.
  CollectionFilter? get galleryFilter => gallery.resolve(outside: _galleryOutside);

  /// Whether the current gallery browsing is restricted.
  bool get galleryRestricted => gallery.isRestricted(outside: _galleryOutside);

  /// Whether the gallery visibility configuration is frozen.
  bool get locked => gallery.locked;

  /// Whether the current range accepts mutations from this page.
  bool get canEdit => !gallery.locked;

  /// Permissions preset the quick lock reuses.
  VisibleRangeLockPreset get lastLockPreset => _lastLockPreset;

  VisibleRangeActiveStyle get activeStyle => _activeStyle;

  VisibleRangeInjectionMode get pinInjectionMode => _pinInjectionMode;

  bool get pinInjectionRemembered => _pinInjectionRemembered;

  Future<void> setActiveStyle(VisibleRangeActiveStyle style) async {
    if (_activeStyle == style) return;
    _activeStyle = style;
    await _requireStore().writeState(VisibleRangeStore.keyActiveStyle, style.name);
    notifyListeners();
  }

  Future<void> setPinInjection({required VisibleRangeInjectionMode mode, required bool remembered}) async {
    // Clearing the remember option is a write too: store the default mode so a
    // later open really starts from automatic instead of silently restoring an
    // old choice behind an unchecked switch.
    final storedMode = remembered ? mode : VisibleRangeInjectionMode.auto;
    _pinInjectionMode = storedMode;
    _pinInjectionRemembered = remembered;
    final store = _requireStore();
    await store.writeState(VisibleRangeStore.keyPinInjectionMode, storedMode.name);
    await store.writeState(VisibleRangeStore.keyPinInjectionRemembered, remembered ? '1' : '0');
    notifyListeners();
  }

  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    final db = injectedDatabase ?? await getIt<AppDatabaseProvider>().open();
    final store = VisibleRangeStore(db);
    _store = store;
    try {
      await _seedDefaults(store);
    } catch (error, stack) {
      // A failed default seed must not hide an already saved range: keep the
      // stored set, skip the version marker and retry on the next start.
      _log.e('failed to seed visible range defaults, keeping the stored set', error, stack);
    }
    try {
      _presets = await store.loadPresets();
      _galleryGroups = await store.loadGroups(VisibleRangeScope.gallery);
      _galleryOutside = await store.loadOutside(VisibleRangeScope.gallery) ?? VisibleRange.emptyOutside(now: _now);
      if (_galleryGroups.isEmpty) {
        final empty = VisibleRange.emptyGallery(now: _now);
        await store.saveRange(empty);
        _galleryGroups = [empty];
      }
      _galleryGroups = await _normalizeGroups(store, _galleryGroups);
      final storedCurrent = await store.readState(VisibleRangeStore.keyCurrentGalleryGroupId);
      _currentGalleryGroupId = _galleryGroups.any((group) => group.id == storedCurrent) ? storedCurrent! : _galleryGroups.first.id;
      if (storedCurrent != _currentGalleryGroupId) {
        await store.writeState(VisibleRangeStore.keyCurrentGalleryGroupId, _currentGalleryGroupId);
      }
      final lastLockPreset = await store.readState(VisibleRangeStore.keyLastLockPreset);
      _lastLockPreset = VisibleRangeLockPreset.values.firstWhere((v) => v.name == lastLockPreset, orElse: () => VisibleRangeLockPreset.readOnly);
      _activeStyle = VisibleRangeActiveStyle.parse(await store.readState(VisibleRangeStore.keyActiveStyle));
      _pinInjectionMode = VisibleRangeInjectionMode.parse(await store.readState(VisibleRangeStore.keyPinInjectionMode));
      _pinInjectionRemembered = await store.readState(VisibleRangeStore.keyPinInjectionRemembered) == '1';
    } catch (error, stack) {
      // A broken range store must never hide the library: fall back to 「不限」.
      _log.e('failed to load visible ranges, falling back to unrestricted', error, stack);
      _galleryGroups = [VisibleRange.emptyGallery(now: _now)];
      _galleryOutside = VisibleRange.emptyOutside(now: _now);
    }
    _initialized = true;
    notifyListeners();
  }

  /// Writes the bundled defaults for the current [VisibleRangeStore.defaultsVersion].
  ///
  /// Base definitions become built-in gallery groups (the old mutually exclusive
  /// scenario set); restriction/supplement definitions become inactive rules of
  /// the shared outside pool. Missing defaults are re-added, but a group is never
  /// pruned: deleting user work to follow a bundle change is worse than keeping a
  /// stale default the user can remove.
  Future<void> _seedDefaults(VisibleRangeStore store) async {
    var outside = await store.loadOutside(VisibleRangeScope.gallery);
    if (outside == null) {
      outside = VisibleRange.emptyOutside(now: _now);
      await store.saveRange(outside);
    }
    // A scope always has one group to browse. Fresh installs start on the
    // unrestricted default; the bundled scenarios are added beside it.
    if ((await store.loadGroups(VisibleRangeScope.gallery)).isEmpty) {
      await store.saveRange(VisibleRange.emptyGallery(now: _now));
    }

    final rawVersion = await store.readState(VisibleRangeStore.keyDefaultsVersion);
    // Installs seeded by the first release only have the boolean marker.
    final legacySeeded = await store.readState(VisibleRangeStore.keySeeded) == '1';
    final seededVersion = int.tryParse(rawVersion ?? '') ?? (legacySeeded ? 1 : 0);
    if (seededVersion >= VisibleRangeStore.defaultsVersion) return;

    if (_usesBundledDefaults) {
      try {
        await _ensureStandardPaths();
      } catch (error, stack) {
        // Without the device's standard directories the camera/pictures defaults
        // would be wrong. Leave the old set in place and retry next start.
        _log.e('failed to resolve standard paths, keeping existing defaults', error, stack);
        return;
      }
    }
    final definitions = await presetLoader();
    // An empty bundle must not burn the marker: the next start with a readable
    // asset still has to seed.
    if (definitions.isEmpty) return;

    final baseDefinitions = definitions.where((definition) => definition.kind == VisibleRangePresetKind.base).toList();
    final groups = await store.loadGroups(VisibleRangeScope.gallery);
    // The default group keeps position 0; the bundled scenarios follow it.
    var position = 1;
    for (final definition in baseDefinitions) {
      final id = visibleRangeBuiltinGroupId(definition.id);
      final existing = groups.firstWhereOrNull((group) => group.id == id);
      if (existing == null) {
        final group = VisibleRange.emptyGroup(
          scope: VisibleRangeScope.gallery,
          id: id,
          name: '@${definition.nameKey}',
          position: position,
          now: _now,
        ).copyWith(
          rules: [
            VisibleRangeRule(
              id: _newId('rule'),
              rangeId: id,
              kind: VisibleRangeRuleKind.source,
              filters: definition.filters,
            ),
          ],
        );
        await store.saveRange(group);
      } else {
        await store.saveRange(
          existing.copyWith(
            // A renamed group keeps its text; a bundled name follows the bundle.
            name: existing.name.isEmpty || existing.name.startsWith('@') ? '@${definition.nameKey}' : existing.name,
            position: position,
            updatedAt: _now,
          ),
        );
      }
      position++;
    }

    // The old global defaults now live in the outside pool, switched off until
    // the user turns them on.
    final outsideRules = [...outside.rules];
    final builtinIds = <String>{};
    final positions = <VisibleRangeRuleKind, int>{};
    for (final definition in definitions) {
      if (definition.kind == VisibleRangePresetKind.base) continue;
      final id = visibleRangeBuiltinRuleId(definition.id);
      builtinIds.add(id);
      final kind = definition.kind == VisibleRangePresetKind.restriction ? VisibleRangeRuleKind.restriction : VisibleRangeRuleKind.supplement;
      final rulePosition = positions[kind] ?? 0;
      positions[kind] = rulePosition + 1;
      final existingIndex = outsideRules.indexWhere((rule) => rule.id == id);
      if (existingIndex < 0) {
        outsideRules.add(
          VisibleRangeRule(
            id: id,
            rangeId: outside.id,
            kind: kind,
            position: rulePosition,
            // `@` marks an ARB key; the page localizes it and a user rename
            // simply replaces the label with plain text.
            label: '@${definition.nameKey}',
            filters: definition.filters,
            active: false,
          ),
        );
      } else {
        outsideRules[existingIndex] = outsideRules[existingIndex].copyWith(position: rulePosition);
      }
    }
    outsideRules.removeWhere((rule) => isVisibleRangeBuiltinRule(rule.id) && !builtinIds.contains(rule.id));
    await store.saveRange(outside.copyWith(rules: outsideRules, updatedAt: _now));

    if (await store.readState(VisibleRangeStore.keyCurrentGalleryGroupId) == null) {
      await store.writeState(VisibleRangeStore.keyCurrentGalleryGroupId, VisibleRange.galleryRangeId);
    }
    await store.writeState(VisibleRangeStore.keyDefaultsVersion, '${VisibleRangeStore.defaultsVersion}');
  }

  /// Makes the stored group list match the sentinel layout.
  ///
  /// Group 0 is always present, empty and first: it is 「Unrestricted」, not a
  /// container, so a pre-refactor base (or a dev build's own rules) must not
  /// linger there. The data groups keep their relative order and are renumbered
  /// from 1.
  Future<List<VisibleRange>> _normalizeGroups(VisibleRangeStore store, List<VisibleRange> groups) async {
    final existingZero = groups.firstWhereOrNull((group) => isGroupZero(group.id));
    var zero = existingZero ?? VisibleRange.emptyGallery(now: _now);
    if (existingZero == null) {
      await store.saveRange(zero);
    } else if (zero.rules.isNotEmpty || zero.position != 0) {
      zero = zero.copyWith(rules: const [], position: 0);
      await store.saveRange(zero);
    }
    final dataGroups = groups.where((group) => !isGroupZero(group.id) && group.kind == VisibleRangeGroupKind.group).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final result = <VisibleRange>[zero];
    for (final group in dataGroups) {
      final position = result.length;
      if (group.position != position) {
        final next = group.copyWith(position: position);
        await store.saveRange(next);
        result.add(next);
      } else {
        result.add(group);
      }
    }
    return result;
  }

  /// Whether the scope-wide outside pool currently narrows anything.
  bool get outsideRestricted => _galleryOutside.hasOwnRestriction;

  /// Persists a whole group as saved by the editor.
  ///
  /// The editor works on a draft, so this is the only write: the group and its
  /// rules are replaced together. A group switched or deleted meanwhile is
  /// refused instead of resurrected.
  Future<void> saveGalleryGroup(VisibleRange group) async {
    _ensureEditable();
    if (isGroupZero(group.id)) return;
    if (!_galleryGroups.any((candidate) => candidate.id == group.id)) return;
    await _saveRange(group.copyWith(updatedAt: _now));
    notifyListeners();
  }

  /// Makes the standard directories available before the asset is parsed.
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

  // groups

  /// Adds a gallery group and makes it current.
  Future<VisibleRange> addGalleryGroup({String name = '', Set<CollectionFilter> filters = const {}}) async {
    _ensureEditable();
    final store = _requireStore();
    final id = _newId('group');
    final group = VisibleRange.emptyGroup(
      scope: VisibleRangeScope.gallery,
      id: id,
      name: name.trim(),
      position: _galleryGroups.length,
      now: _now,
    ).copyWith(
      rules: filters.isEmpty
          ? const []
          : [
              VisibleRangeRule(
                id: _newId('rule'),
                rangeId: id,
                kind: VisibleRangeRuleKind.source,
                label: name.trim(),
                filters: filters,
              ),
            ],
    );
    await store.saveRange(group);
    _galleryGroups = [..._galleryGroups, group];
    _currentGalleryGroupId = id;
    await store.writeState(VisibleRangeStore.keyCurrentGalleryGroupId, id);
    notifyListeners();
    return group;
  }

  Future<void> renameGalleryGroup(String id, {required String name}) async {
    _ensureEditable();
    if (isGroupZero(id)) return;
    final group = galleryGroupById(id);
    if (group == null) return;
    await _saveRange(group.copyWith(name: name.trim(), updatedAt: _now));
    notifyListeners();
  }

  /// Makes [id] the current group; browsing re-resolves on the notification.
  Future<void> selectGalleryGroup(String id) async {
    _ensureEditable();
    if (!_galleryGroups.any((group) => group.id == id) || id == _currentGalleryGroupId) return;
    _currentGalleryGroupId = id;
    await _requireStore().writeState(VisibleRangeStore.keyCurrentGalleryGroupId, id);
    notifyListeners();
  }

  /// Deletes data groups, keeping group 0 and the current pointer valid.
  Future<bool> deleteGalleryGroups(Set<String> ids) async {
    _ensureEditable();
    final deletable = ids.where((id) => !isGroupZero(id)).toSet();
    if (deletable.isEmpty) return false;
    final remaining = _galleryGroups.where((group) => !deletable.contains(group.id)).toList();
    if (remaining.where((group) => !isGroupZero(group.id)).isEmpty) return false;
    final store = _requireStore();
    for (final id in deletable) {
      await store.deleteRange(id);
    }
    _galleryGroups = remaining;
    for (var i = 0; i < remaining.length; i++) {
      if (remaining[i].position != i) {
        remaining[i] = remaining[i].copyWith(position: i);
        await store.saveRange(remaining[i]);
      }
    }
    if (!remaining.any((group) => group.id == _currentGalleryGroupId)) {
      _currentGalleryGroupId = remaining.first.id;
      await store.writeState(VisibleRangeStore.keyCurrentGalleryGroupId, _currentGalleryGroupId);
    }
    notifyListeners();
    return true;
  }

  /// Moves a group by [delta] inside the display order, never across group 0.
  Future<void> moveGalleryGroup(String id, int delta) async {
    _ensureEditable();
    if (isGroupZero(id)) return;
    final index = _galleryGroups.indexWhere((group) => group.id == id);
    final target = index + delta;
    if (index < 0 || target < 1 || target >= _galleryGroups.length) return;
    final reordered = [..._galleryGroups];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);
    _galleryGroups = reordered;
    for (var i = 0; i < reordered.length; i++) {
      await _saveRange(reordered[i].copyWith(position: i, updatedAt: _now));
    }
    notifyListeners();
  }

  // conditions

  /// Adds a condition to [rangeId] (default: the current group).
  Future<VisibleRangeRule?> addRule({
    required VisibleRangeRuleKind kind,
    required Set<CollectionFilter> filters,
    String label = '',
    String? rangeId,
  }) async {
    _ensureEditable();
    if (filters.isEmpty) return null;
    final range = await _requireRange(rangeId ?? gallery.id);
    if (range == null || isGroupZero(range.id)) return null;
    if (range.isOutside && !kind.isOutsideAllowed) return null;
    final rule = VisibleRangeRule(
      id: _newId('rule'),
      rangeId: range.id,
      kind: kind,
      position: range.rulesOf(kind).length,
      label: label,
      filters: filters,
    );
    await _saveRange(range.copyWith(rules: [...range.rules, rule], updatedAt: _now));
    notifyListeners();
    return rule;
  }

  Future<void> updateRule(VisibleRangeRule rule) async {
    _ensureEditable();
    final range = await _requireRange(rule.rangeId);
    if (range == null || isGroupZero(range.id)) return;
    await _saveRange(range.copyWith(rules: [for (final candidate in range.rules) candidate.id == rule.id ? rule : candidate], updatedAt: _now));
    notifyListeners();
  }

  Future<void> toggleRule(String id) async {
    _ensureEditable();
    final range = await _rangeOfRule(id);
    if (range == null || isGroupZero(range.id)) return;
    await _saveRange(
      range.copyWith(rules: [for (final rule in range.rules) rule.id == id ? rule.copyWith(active: !rule.active) : rule], updatedAt: _now),
    );
    notifyListeners();
  }

  Future<void> deleteRules(Set<String> ids) async {
    _ensureEditable();
    if (ids.isEmpty) return;
    for (final range in [..._galleryGroups, _galleryOutside]) {
      if (isGroupZero(range.id)) continue;
      if (!range.rules.any((rule) => ids.contains(rule.id))) continue;
      await _saveRange(range.copyWith(rules: range.rules.where((rule) => !ids.contains(rule.id)).toList(), updatedAt: _now));
    }
    notifyListeners();
  }

  /// Moves a condition to another role, appended after the rules already there.
  Future<void> moveRuleToKind(String rangeId, String ruleId, VisibleRangeRuleKind kind) async {
    _ensureEditable();
    final range = await _requireRange(rangeId);
    final rule = range?.ruleById(ruleId);
    if (range == null || rule == null || rule.kind == kind || isGroupZero(range.id)) return;
    if (range.isOutside && !kind.isOutsideAllowed) return;
    final moved = rule.copyWith(kind: kind, position: range.rulesOf(kind).length);
    await _saveRange(range.copyWith(rules: [for (final candidate in range.rules) candidate.id == ruleId ? moved : candidate], updatedAt: _now));
    notifyListeners();
  }

  Future<void> setOrder(VisibleRangeOrder order, {String? rangeId}) async {
    _ensureEditable();
    final range = await _requireRange(rangeId ?? gallery.id);
    if (range == null || isGroupZero(range.id)) return;
    await _saveRange(range.copyWith(order: order, updatedAt: _now));
    notifyListeners();
  }

  /// Replaces the current group's source conditions with [filters].
  Future<void> selectBase({required String presetId, required String name, required Set<CollectionFilter> filters}) => _replaceSources(gallery.id, filters, name);

  Future<void> clearBase() => _replaceSources(gallery.id, const {}, '');

  /// Clears the source conditions of [rangeId] (the current group by default).
  Future<void> clearSources([String? rangeId]) => _replaceSources(rangeId ?? gallery.id, const {}, '');

  /// Adds [filters] as one source condition of [rangeId].
  Future<void> addSource(String rangeId, Set<CollectionFilter> filters, {String label = ''}) async {
    _ensureEditable();
    final range = await _requireRange(rangeId);
    if (range == null || isGroupZero(range.id) || filters.isEmpty) return;
    final rule = VisibleRangeRule(
      id: _newId('rule'),
      rangeId: range.id,
      kind: VisibleRangeRuleKind.source,
      position: range.rulesOf(VisibleRangeRuleKind.source).length,
      label: label,
      filters: filters,
    );
    await _saveRange(range.copyWith(rules: [...range.rules, rule], updatedAt: _now));
    notifyListeners();
  }

  Future<void> _replaceSources(String rangeId, Set<CollectionFilter> filters, String label) async {
    _ensureEditable();
    final range = await _requireRange(rangeId);
    if (range == null || isGroupZero(range.id)) return;
    final kept = range.rules.where((rule) => rule.kind != VisibleRangeRuleKind.source).toList();
    final rules = filters.isEmpty
        ? kept
        : [
            ...kept,
            VisibleRangeRule(
              id: _newId('rule'),
              rangeId: range.id,
              kind: VisibleRangeRuleKind.source,
              label: label,
              filters: filters,
            ),
          ];
    await _saveRange(range.copyWith(rules: rules, updatedAt: _now));
    notifyListeners();
  }

  // defaults

  /// Re-adds the bundled groups and outside rules, skipping what is present.
  Future<({int added, int skipped})> reAddDefaultPresets() async {
    _ensureEditable();
    if (_usesBundledDefaults) {
      try {
        await _ensureStandardPaths();
      } catch (error, stack) {
        _log.e('failed to resolve standard paths, cannot re-add defaults', error, stack);
        return (added: 0, skipped: 0);
      }
    }
    final definitions = await presetLoader();
    var added = 0;
    var skipped = 0;
    final groups = _galleryGroups;
    for (final definition in definitions.where((definition) => definition.kind == VisibleRangePresetKind.base)) {
      final id = visibleRangeBuiltinGroupId(definition.id);
      if (groups.any((group) => group.id == id)) {
        skipped++;
        continue;
      }
      final group = VisibleRange.emptyGroup(
        scope: VisibleRangeScope.gallery,
        id: id,
        name: '@${definition.nameKey}',
        position: _galleryGroups.length + added,
        now: _now,
      ).copyWith(
        rules: [
          VisibleRangeRule(
            id: _newId('rule'),
            rangeId: id,
            kind: VisibleRangeRuleKind.source,
            filters: definition.filters,
          ),
        ],
      );
      await _saveRange(group);
      added++;
    }
    final outside = _galleryOutside;
    final rules = [...outside.rules];
    for (final definition in definitions.where((definition) => definition.kind != VisibleRangePresetKind.base)) {
      final id = visibleRangeBuiltinRuleId(definition.id);
      if (rules.any((rule) => rule.id == id)) {
        skipped++;
        continue;
      }
      final kind = definition.kind == VisibleRangePresetKind.restriction ? VisibleRangeRuleKind.restriction : VisibleRangeRuleKind.supplement;
      rules.add(
        VisibleRangeRule(
          id: id,
          rangeId: outside.id,
          kind: kind,
          position: rules.where((rule) => rule.kind == kind).length,
          label: '@${definition.nameKey}',
          filters: definition.filters,
          active: false,
        ),
      );
      added++;
    }
    if (added > 0) {
      await _saveRange(outside.copyWith(rules: rules, updatedAt: _now));
    }
    notifyListeners();
    return (added: added, skipped: skipped);
  }

  /// Group templates are groups now; the action creates one from the filters.
  Future<void> saveBasePreset({required String name, String description = '', required Set<CollectionFilter> filters}) => addGalleryGroup(name: name, filters: filters);

  Future<void> updateBasePreset(String id, {required String name, required String description}) => renameGalleryGroup(id, name: name);

  Future<void> deleteBasePreset(String id) => deleteGalleryGroups({id});

  // lock

  Future<void> lockWithPreset(VisibleRangeLockPreset preset) async {
    _lastLockPreset = preset;
    await _requireStore().writeState(VisibleRangeStore.keyLastLockPreset, preset.name);
    await lock(permissions: VisibleRangePermissions.of(preset));
  }

  Future<void> lock({required VisibleRangePermissions permissions}) async {
    final group = gallery;
    await _saveRange(group.copyWith(locked: true, permissions: permissions, updatedAt: _now));
    notifyListeners();
  }

  Future<void> unlock() async {
    final group = gallery;
    if (!group.locked) return;
    await _saveRange(group.copyWith(locked: false, updatedAt: _now));
    notifyListeners();
  }

  // targets

  /// Extra range surfaces (the wallpaper groups), set by the composition root.
  VisibleRangeTargetSource? targetSource;

  /// Every place the current filters can be saved to.
  ///
  /// Group 0 is not a target: it is 「Unrestricted」, so writing conditions into
  /// it would make the state it stands for impossible. The wallpaper group 0 is
  /// excluded by its own source for the same reason.
  Future<List<VisibleRangePinTarget>> loadPinTargets() async {
    final extra = targetSource == null ? const <VisibleRangePinTarget>[] : await targetSource!.loadPinTargets();
    final galleryLocked = gallery.locked;
    return [
      for (final group in _galleryGroups)
        if (!isGroupZero(group.id))
          VisibleRangePinTarget(
            id: group.id,
            rangeId: group.id,
            kind: VisibleRangePinTargetKind.galleryGroup,
            number: galleryGroupNumber(group.id),
            name: group.name,
            locked: galleryLocked,
          ),
      for (final role in VisibleRangeRuleKind.outsideRoles)
        VisibleRangePinTarget(
          id: '${_galleryOutside.id}.${role.name}',
          rangeId: _galleryOutside.id,
          kind: VisibleRangePinTargetKind.outside,
          role: role,
          number: 0,
          locked: galleryLocked,
        ),
      ...extra,
    ];
  }

  /// Pins [request.filters] to every selected target in one write.
  Future<VisibleRangePinResult> pinFilters(VisibleRangePinRequest request) async {
    if (request.isEmpty) return const VisibleRangePinResult(pinned: 0, skipped: 0);
    final requested = request.targetIds;
    final targets = (await loadPinTargets()).where((target) => requested.contains(target.id) && !target.locked).toList();
    var skipped = requested.length - targets.length;
    if (targets.isEmpty) return VisibleRangePinResult(pinned: 0, skipped: skipped);

    var pinned = 0;
    for (final target in targets) {
      final range = await _loadRangeById(target.rangeId);
      if (range == null || isGroupZero(range.id)) {
        skipped++;
        continue;
      }
      await _saveRange(_pinToRange(range, target, request));
      pinned++;
    }
    notifyListeners();
    return VisibleRangePinResult(pinned: pinned, skipped: skipped);
  }

  /// Applies one pin request to a single range.
  ///
  /// New conditions follow [VisibleRangePinRequest.injection]: [auto] enables
  /// everything only when the target group has no conditions yet, so a second pin
  /// lands parked and the user turns it on deliberately. Re-pinning an existing
  /// condition keeps its state. The outside pool has no attributes: its two
  /// targets put every filter in their own role.
  VisibleRange _pinToRange(VisibleRange range, VisibleRangePinTarget target, VisibleRangePinRequest request) {
    final name = request.name.trim();
    final isWallpaper = range.scope == VisibleRangeScope.wallpaper;
    final existingRules = request.writeMode == VisibleRangePinWriteMode.replace ? <VisibleRangeRule>[] : [...range.rules];
    final enableNew = switch (request.injection) {
      VisibleRangeInjectionMode.enable => true,
      VisibleRangeInjectionMode.park => false,
      VisibleRangeInjectionMode.auto => target.isOutside || existingRules.every((rule) => rule.filters.isEmpty),
    };

    var rules = existingRules;
    void upsert(VisibleRangeRuleKind kind, Set<CollectionFilter> filters, {String label = ''}) {
      if (filters.isEmpty) return;
      final fingerprint = filterFingerprint(filters);
      final existing = rules.firstWhereOrNull((rule) => rule.kind == kind && filterFingerprint(rule.filters) == fingerprint);
      if (existing != null) {
        rules = [
          for (final rule in rules)
            rule.id == existing.id ? rule.copyWith(label: label.isEmpty ? rule.label : label, description: request.description) : rule,
        ];
        return;
      }
      rules = [
        ...rules,
        VisibleRangeRule(
          id: _newId('rule'),
          rangeId: range.id,
          kind: kind,
          position: rules.where((rule) => rule.kind == kind).length,
          label: label,
          description: request.description,
          filters: filters,
          // A wallpaper condition is enabled per surface; a parked one keeps 0
          // and stays listed in the pool.
          active: isWallpaper ? true : enableNew,
          surfaces: isWallpaper ? (enableNew ? 3 : 0) : 0,
        ),
      ];
    }

    if (target.isOutside) {
      final role = target.role ?? VisibleRangeRuleKind.restriction;
      for (final filter in request.filters) {
        upsert(role, {filter}, label: name);
      }
      return range.copyWith(rules: rules, updatedAt: _now);
    }

    final split = splitVisibleRangePin(request.filters, forcedRole: request.forcedRole);
    final oneRule = split.sources.length + split.restrictions.length + split.supplements.length == 1;
    for (final source in split.sources) {
      upsert(VisibleRangeRuleKind.source, source, label: oneRule ? name : '');
    }
    for (final filter in split.restrictions) {
      upsert(VisibleRangeRuleKind.restriction, {filter}, label: oneRule ? name : '');
    }
    for (final filter in split.supplements) {
      upsert(VisibleRangeRuleKind.supplement, {filter}, label: oneRule ? name : '');
    }
    return range.copyWith(rules: rules, updatedAt: _now);
  }

  // applied targets

  /// Remembers that [candidates] opened a media set, so the pin sheet can offer
  /// to write the current filters back to them later.
  Future<void> markAppliedTargets({required String rangeId, required Iterable<VisibleRangeCandidate> candidates}) async {
    final store = _requireStore();
    final now = _now;
    for (final candidate in candidates) {
      final rule = candidate.rule;
      final usage = rule != null
          ? VisibleRangeRuleUsage.forRule(ruleId: rule.id, rangeId: rangeId, kind: rule.kind, usedAt: now)
          : VisibleRangeRuleUsage.forBase(rangeId: rangeId, usedAt: now);
      await store.saveUsage(usage);
    }
  }

  /// Every remembered target, resolved for the write-back list.
  Future<List<VisibleRangeWriteBackTarget>> loadAppliedTargets() async {
    final store = _requireStore();
    final usages = await store.loadUsages();
    if (usages.isEmpty) return const [];
    final targets = await loadPinTargets();
    final owners = {for (final target in targets) target.rangeId: target};
    final ranges = <String, VisibleRange?>{};
    final result = <VisibleRangeWriteBackTarget>[];
    for (final usage in usages) {
      final range = ranges[usage.rangeId] ??= await _loadRangeById(usage.rangeId);
      if (range == null) continue;
      // A legacy base usage addresses the source the base migrated to.
      final rule = usage.isBase ? range.rulesOf(VisibleRangeRuleKind.source).firstOrNull : range.ruleById(usage.targetId);
      if (rule == null) continue;
      final owner = owners[range.id] ?? owners[usage.rangeId];
      result.add(
        VisibleRangeWriteBackTarget(
          usageId: usage.id,
          rangeId: usage.rangeId,
          targetId: usage.targetId,
          kind: usage.kind,
          isGallery: range.scope == VisibleRangeScope.gallery,
          number: owner?.number ?? 0,
          ownerName: owner?.name ?? '',
          label: rule.label,
          filters: rule.filters,
          locked: !_canWrite(range),
        ),
      );
    }
    return result;
  }

  /// Writes [filters] over the selected remembered targets.
  Future<VisibleRangeWriteBackResult> writeBackTargets({
    required Set<String> usageIds,
    required Set<CollectionFilter> filters,
    required String baseName,
  }) async {
    if (usageIds.isEmpty || filters.isEmpty) return const VisibleRangeWriteBackResult(written: 0, skipped: 0);
    final store = _requireStore();
    final usages = (await store.loadUsages()).where((usage) => usageIds.contains(usage.id)).toList();
    final byRange = groupBy(usages, (usage) => usage.rangeId);
    var written = 0;
    var skipped = 0;
    for (final entry in byRange.entries) {
      final range = await _loadRangeById(entry.key);
      if (range == null || !_canWrite(range)) {
        skipped += entry.value.length;
        continue;
      }
      var next = range;
      for (final usage in entry.value) {
        final rule = usage.isBase ? next.rulesOf(VisibleRangeRuleKind.source).firstOrNull : next.ruleById(usage.targetId);
        if (rule == null) {
          skipped++;
          continue;
        }
        next = next.copyWith(
          rules: [
            for (final candidate in next.rules)
              if (candidate.id == rule.id) candidate.copyWith(filters: filters, label: candidate.label.isEmpty ? baseName.trim() : candidate.label) else candidate,
          ],
        );
        written++;
      }
      if (next == range) continue;
      await _saveRange(next.copyWith(updatedAt: _now));
    }
    if (written > 0) notifyListeners();
    return VisibleRangeWriteBackResult(written: written, skipped: skipped);
  }

  // internals

  bool _canWrite(VisibleRange range) => range.scope == VisibleRangeScope.gallery ? !gallery.locked : !range.locked || range.permissions.edit;

  Future<VisibleRange?> _requireRange(String id) async => _loadRangeById(id);

  Future<VisibleRange?> _rangeOfRule(String ruleId) async {
    for (final range in [..._galleryGroups, _galleryOutside]) {
      if (range.rules.any((rule) => rule.id == ruleId)) return range;
    }
    return null;
  }

  /// Loads a range by id from whichever surface owns it.
  Future<VisibleRange?> _loadRangeById(String rangeId) async {
    if (rangeId == _galleryOutside.id) return _galleryOutside;
    final group = _galleryGroups.firstWhereOrNull((candidate) => candidate.id == rangeId);
    if (group != null) return group;
    return targetSource?.loadRange(rangeId);
  }

  /// Persists a range back to its owner, keeping the in-memory list in sync.
  Future<void> _saveRange(VisibleRange range) async {
    // Group 0 stands for 「Unrestricted」: a stray condition would make the
    // sentinel mean nothing, so it is refused rather than stored and hidden.
    if (isGroupZero(range.id) && range.rules.isNotEmpty) return;
    final store = _requireStore();
    if (range.id == _galleryOutside.id) {
      await store.saveRange(range);
      _galleryOutside = range;
      return;
    }
    final index = _galleryGroups.indexWhere((group) => group.id == range.id);
    if (index >= 0) {
      await store.saveRange(range);
      _galleryGroups = [for (final group in _galleryGroups) group.id == range.id ? range : group];
      return;
    }
    await targetSource?.saveRange(range);
  }

  void _ensureEditable() {
    if (!canEdit) throw StateError('visible range is locked');
  }

  VisibleRangeStore _requireStore() {
    final store = _store;
    if (store != null) return store;
    throw StateError('VisibleRangeController is not initialized');
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  String _newId(String prefix) => '$prefix.$_now.${_idCounter++}';
}

/// The process-wide controller.
final visibleRangeController = VisibleRangeController();
