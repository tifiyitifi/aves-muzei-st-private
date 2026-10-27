import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/model/visible_range_pin.dart';
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

/// The single source of truth for visible ranges.
///
/// It is a `ChangeNotifier` rather than a provider-held notifier because the
/// current range is consulted from synchronous, non-widget seams (the collection
/// source and the paged engine router). Widgets subscribe through
/// `context.watch`/`AnimatedBuilder`, and the collection surfaces refresh on
/// [notifyListeners] instead of polling.
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
  VisibleRange? _gallery;
  List<VisibleRangePreset> _presets = const [];
  VisibleRangeLockPreset _lastLockPreset = VisibleRangeLockPreset.readOnly;
  VisibleRangeActiveStyle _activeStyle = VisibleRangeActiveStyle.section;
  Future<void>? _initFuture;
  bool _initialized = false;

  bool get initialized => _initialized;

  VisibleRange get gallery => _gallery ?? VisibleRange.emptyGallery();

  List<VisibleRangePreset> get presets => _presets;

  /// The filter resolved from the current gallery range, or null for 「不限」.
  CollectionFilter? get galleryFilter => gallery.resolve();

  /// Whether the current gallery browsing is restricted.
  bool get galleryRestricted => gallery.isRestricted;

  bool get locked => gallery.locked;

  /// Whether the current range accepts mutations from this page.
  bool get canEdit => !gallery.locked || gallery.permissions.edit;

  /// Permissions preset the quick lock reuses.
  VisibleRangeLockPreset get lastLockPreset => _lastLockPreset;

  VisibleRangeActiveStyle get activeStyle => _activeStyle;

  Future<void> setActiveStyle(VisibleRangeActiveStyle style) async {
    if (_activeStyle == style) return;
    _activeStyle = style;
    await _requireStore().writeState(VisibleRangeStore.keyActiveStyle, style.name);
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
      _gallery = await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId) ?? VisibleRange.emptyGallery(now: _now);
      final lastLockPreset = await store.readState(VisibleRangeStore.keyLastLockPreset);
      _lastLockPreset = VisibleRangeLockPreset.values.firstWhere(
        (v) => v.name == lastLockPreset,
        orElse: () => VisibleRangeLockPreset.readOnly,
      );
      _activeStyle = VisibleRangeActiveStyle.parse(await store.readState(VisibleRangeStore.keyActiveStyle));
      _initialized = true;
    } catch (error, stack) {
      // A broken range store must never hide the library: fall back to 「不限」.
      _log.e('failed to load visible ranges, falling back to unrestricted', error, stack);
      _gallery = VisibleRange.emptyGallery(now: _now);
      _initialized = true;
    }
    notifyListeners();
  }

  /// Writes the bundled defaults for the current [VisibleRangeStore.defaultsVersion].
  ///
  /// Base candidates become presets; restriction and supplement candidates become
  /// inactive rules, so the page can show them as tiles before the user turns
  /// them on.
  ///
  /// A version bump also re-applies the bundled order and prunes entries the
  /// bundle dropped. Deleted defaults coming back is intended (see
  /// [VisibleRangeStore.defaultsVersion]): the bundle stays the single source of
  /// truth, while the user's activation, rename and description on a kept
  /// default survive the reorder.
  Future<void> _seedDefaults(VisibleRangeStore store) async {
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
    if (seededVersion < 2) {
      await store.deleteBuiltinPresets();
    } else {
      // The bundle is curated: drop built-ins it no longer ships, keeping the
      // user's own presets. Later versions prune instead of wiping, so a bump
      // does not renumber the user's saved positions.
      await store.deleteBuiltinPresetsExcept(baseDefinitions.map((definition) => definition.id).toSet());
    }
    var position = 0;
    for (final definition in baseDefinitions) {
      await store.savePreset(
        VisibleRangePreset(
          id: definition.id,
          name: definition.nameKey,
          filters: definition.filters,
          builtin: true,
          position: position++,
        ),
      );
    }

    final range = await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId) ?? VisibleRange.emptyGallery(now: _now);
    final rules = [...range.rules];
    final builtinIds = <String>{};
    final positions = <VisibleRangeRuleKind, int>{};
    for (final definition in definitions) {
      if (definition.kind == VisibleRangePresetKind.base) continue;
      final id = _builtinRuleId(definition.id);
      builtinIds.add(id);
      final kind = definition.kind == VisibleRangePresetKind.restriction ? VisibleRangeRuleKind.restriction : VisibleRangeRuleKind.supplement;
      final rulePosition = positions[kind] ?? 0;
      positions[kind] = rulePosition + 1;
      final existingIndex = rules.indexWhere((rule) => rule.id == id);
      if (existingIndex < 0) {
        rules.add(
          VisibleRangeRule(
            id: id,
            rangeId: range.id,
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
        // Re-apply the bundled order, but keep the activation, rename and
        // description the user already made on this default.
        rules[existingIndex] = rules[existingIndex].copyWith(position: rulePosition);
      }
    }
    // A version bump may also drop a default and with it its activation state;
    // user rules stay untouched.
    rules.removeWhere((rule) => _isBuiltinRule(rule.id) && !builtinIds.contains(rule.id));
    await store.saveRange(range.copyWith(rules: rules));
    await store.writeState(VisibleRangeStore.keyDefaultsVersion, '${VisibleRangeStore.defaultsVersion}');
  }

  /// Makes the standard directories available before the asset is parsed.
  ///
  /// `androidFileUtils.init` runs after the first frame otherwise; defaults are
  /// only seeded on a fresh install or a defaults bump, so this one-time wait
  /// does not affect normal startup. A device that is still booting reports no
  /// storage volume: skip the seed instead of blocking the first frame on its
  /// retry loop, and try again on the next start.
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

  static String _builtinRuleId(String definitionId) => visibleRangeBuiltinRuleId(definitionId);

  static bool _isBuiltinRule(String id) => isVisibleRangeBuiltinRule(id);

  // presets

  /// Re-adds the bundled candidates, skipping ids and filter fingerprints that
  /// are already present. Returns how many were added and skipped.
  ///
  /// Restriction and supplement defaults are restored as inactive rules, so a
  /// deleted default comes back switched off instead of silently changing the
  /// current range.
  Future<({int added, int skipped})> reAddDefaultPresets() async {
    final store = _requireStore();
    if (gallery.locked) return (added: 0, skipped: 0);
    if (_usesBundledDefaults) {
      try {
        await _ensureStandardPaths();
      } catch (error, stack) {
        _log.e('failed to resolve standard paths, cannot re-add defaults', error, stack);
        return (added: 0, skipped: 0);
      }
    }
    final definitions = await presetLoader();
    final existingIds = _presets.map((v) => v.id).toSet();
    final existingFingerprints = _presets.map((v) => v.fingerprint).toSet();
    var added = 0;
    var skipped = 0;
    var position = _presets.length;
    for (final definition in definitions.where((definition) => definition.kind == VisibleRangePresetKind.base)) {
      final preset = VisibleRangePreset(
        id: definition.id,
        name: definition.nameKey,
        filters: definition.filters,
        builtin: true,
        position: position,
      );
      if (existingIds.contains(preset.id) || existingFingerprints.contains(preset.fingerprint)) {
        skipped++;
        continue;
      }
      await store.savePreset(preset);
      position++;
      added++;
    }
    _presets = await store.loadPresets();

    final range = gallery;
    final rules = [...range.rules];
    var rulesAdded = 0;
    final positions = <VisibleRangeRuleKind, int>{
      for (final kind in VisibleRangeRuleKind.values) kind: rules.where((rule) => rule.kind == kind).length,
    };
    for (final definition in definitions.where((definition) => definition.kind != VisibleRangePresetKind.base)) {
      final id = _builtinRuleId(definition.id);
      if (rules.any((rule) => rule.id == id)) {
        skipped++;
        continue;
      }
      final kind = definition.kind == VisibleRangePresetKind.restriction ? VisibleRangeRuleKind.restriction : VisibleRangeRuleKind.supplement;
      final rulePosition = positions[kind] ?? 0;
      positions[kind] = rulePosition + 1;
      rules.add(
        VisibleRangeRule(
          id: id,
          rangeId: range.id,
          kind: kind,
          position: rulePosition,
          label: '@${definition.nameKey}',
          filters: definition.filters,
          active: false,
        ),
      );
      rulesAdded++;
      added++;
    }
    if (rulesAdded > 0) {
      await _updateGallery((range) => range.copyWith(rules: rules));
    }

    notifyListeners();
    return (added: added, skipped: skipped);
  }

  Future<void> saveBasePreset({required String name, String description = '', required Set<CollectionFilter> filters}) async {
    _ensureEditable();
    final store = _requireStore();
    final preset = VisibleRangePreset(
      id: _newId('user'),
      name: name,
      description: description,
      filters: filters,
      position: _presets.length,
    );
    await store.savePreset(preset);
    _presets = await store.loadPresets();
    notifyListeners();
  }

  /// Renames a user base preset and edits its note. Built-in presets are
  /// read-only. When the preset is the active base, the range snapshot follows
  /// so the footer shows the new name immediately.
  Future<void> updateBasePreset(String id, {required String name, required String description}) async {
    _ensureEditable();
    final preset = _presets.firstWhereOrNull((v) => v.id == id);
    if (preset == null || preset.builtin) return;
    await _requireStore().savePreset(preset.copyWith(name: name, description: description));
    _presets = [for (final p in _presets) p.id == id ? p.copyWith(name: name, description: description) : p];
    if (gallery.basePresetId == id && gallery.baseName != name) {
      await _updateGallery((range) => range.copyWith(baseName: name));
    } else {
      notifyListeners();
    }
  }

  Future<void> deleteBasePreset(String id) async {
    _ensureEditable();
    final preset = _presets.firstWhereOrNull((v) => v.id == id);
    if (preset == null || preset.builtin) return;
    await _requireStore().deletePreset(id);
    _presets = _presets.where((v) => v.id != id).toList();
    notifyListeners();
  }

  // base / rules

  Future<void> selectBase({required String presetId, required String name, required Set<CollectionFilter> filters}) async {
    _ensureEditable();
    await _updateGallery(
      (range) => range.copyWith(basePresetId: presetId, baseName: name, baseFilters: filters),
    );
  }

  Future<void> clearBase() async {
    _ensureEditable();
    await _updateGallery((range) => range.copyWith(basePresetId: '', baseName: '', baseFilters: {}));
  }

  Future<VisibleRangeRule?> addRule({
    required VisibleRangeRuleKind kind,
    required Set<CollectionFilter> filters,
    String label = '',
  }) async {
    _ensureEditable();
    if (filters.isEmpty) return null;
    final range = gallery;
    final position = range.rulesOf(kind).length;
    final rule = VisibleRangeRule(
      id: _newId('rule'),
      rangeId: range.id,
      kind: kind,
      position: position,
      label: label,
      filters: filters,
    );
    await _updateGallery((range) => range.copyWith(rules: [...range.rules, rule]));
    return rule;
  }

  Future<void> updateRule(VisibleRangeRule rule) async {
    _ensureEditable();
    await _updateGallery((range) => range.copyWith(rules: [for (final r in range.rules) r.id == rule.id ? rule : r]));
  }

  Future<void> toggleRule(String id) async {
    _ensureEditable();
    await _updateGallery(
      (range) => range.copyWith(rules: [for (final rule in range.rules) rule.id == id ? rule.copyWith(active: !rule.active) : rule]),
    );
  }

  Future<void> deleteRules(Set<String> ids) async {
    _ensureEditable();
    if (ids.isEmpty) return;
    await _updateGallery((range) => range.copyWith(rules: range.rules.where((rule) => !ids.contains(rule.id)).toList()));
  }

  Future<void> setOrder(VisibleRangeOrder order) async {
    _ensureEditable();
    await _updateGallery((range) => range.copyWith(order: order));
  }

  // targets

  /// Extra range surfaces (the wallpaper groups), set by the composition root.
  ///
  /// It is a plain field rather than a constructor argument so a test can leave
  /// it unset: the gallery range then stands alone.
  VisibleRangeTargetSource? targetSource;

  /// Every place the current filters can be pinned to: the gallery first, then
  /// the registered wallpaper groups in badge order.
  Future<List<VisibleRangePinTarget>> loadPinTargets() async {
    final extra = targetSource == null ? const <VisibleRangePinTarget>[] : await targetSource!.loadPinTargets();
    return [
      VisibleRangePinTarget(
        rangeId: gallery.id,
        number: 0,
        name: '',
        isGallery: true,
        locked: !canEdit,
      ),
      ...extra,
    ];
  }

  /// Pins [request.filters] to every selected target and group in one write.
  ///
  /// A locked or unknown target is skipped instead of failing the request, so
  /// the sheet can offer the gallery and the groups side by side. Re-pinning the
  /// same conditions to the same target updates the existing item (name,
  /// description, active) instead of stacking a duplicate. The base is a preset
  /// shared by all targets, so it is created/reused once and then selected per
  /// target.
  Future<VisibleRangePinResult> pinFilters(VisibleRangePinRequest request) async {
    if (request.filters.isEmpty || request.kinds.isEmpty || request.targetRangeIds.isEmpty) {
      return const VisibleRangePinResult(pinned: 0, skipped: 0);
    }
    final store = _requireStore();
    final requested = request.targetRangeIds;
    final targets = (await loadPinTargets()).where((target) => requested.contains(target.rangeId) && !target.locked).toList();
    var skipped = requested.length - targets.length;
    if (targets.isEmpty) return VisibleRangePinResult(pinned: 0, skipped: skipped);

    final fingerprint = filterFingerprint(request.filters);
    final name = request.name.trim();

    // The base lives in the global preset catalog, so one preset serves every
    // target. Reusing it keeps the page from growing a duplicate per pin.
    VisibleRangePreset? preset;
    if (request.kinds.contains(VisibleRangeCandidateKind.base)) {
      final existing = _presets.firstWhereOrNull((p) => !p.builtin && p.fingerprint == fingerprint && p.name == name);
      if (existing != null) {
        preset = existing;
        if (existing.description != request.description) {
          preset = existing.copyWith(description: request.description);
          await store.savePreset(preset);
        }
      } else {
        preset = VisibleRangePreset(
          id: _newId('user'),
          name: name,
          description: request.description,
          filters: request.filters,
          position: _presets.length,
        );
        await store.savePreset(preset);
      }
      // Reload before the range write so listeners observe both together.
      _presets = await store.loadPresets();
    }

    var pinned = 0;
    for (final target in targets) {
      final range = await _loadRangeById(target.rangeId);
      if (range == null) {
        skipped++;
        continue;
      }
      await _saveRange(_pinToRange(range, request, preset, fingerprint, name));
      pinned++;
    }
    notifyListeners();
    return VisibleRangePinResult(pinned: pinned, skipped: skipped);
  }

  /// Applies one pin request to a single range.
  ///
  /// Rules are matched by kind and filter fingerprint, so re-pinning the same
  /// conditions refreshes the existing rule rather than adding a twin.
  VisibleRange _pinToRange(VisibleRange range, VisibleRangePinRequest request, VisibleRangePreset? preset, String fingerprint, String name) {
    var rules = [...range.rules];
    for (final kind in request.kinds) {
      final ruleKind = kind.ruleKind;
      if (ruleKind == null) continue;
      final existing = rules.firstWhereOrNull((rule) => rule.kind == ruleKind && filterFingerprint(rule.filters) == fingerprint);
      if (existing != null) {
        rules = [
          for (final rule in rules)
            rule.id == existing.id ? rule.copyWith(label: name, description: request.description, active: true) : rule
        ];
      } else {
        rules.add(
          VisibleRangeRule(
            id: _newId('rule'),
            rangeId: range.id,
            kind: ruleKind,
            position: rules.where((rule) => rule.kind == ruleKind).length,
            label: name,
            description: request.description,
            filters: request.filters,
          ),
        );
      }
    }
    return range.copyWith(
      basePresetId: preset?.id ?? range.basePresetId,
      baseName: preset?.name ?? range.baseName,
      baseFilters: preset?.filters ?? range.baseFilters,
      rules: rules,
      updatedAt: _now,
    );
  }

  // applied targets

  /// Remembers that [candidates] opened a media set, so the pin sheet can offer
  /// to write the current filters back to them later.
  ///
  /// A rule target is addressed by its global, never reused id; a base target by
  /// its range, because the base has no id of its own. Usage is a set, so taking
  /// the same rule out twice keeps one row (and a fresh timestamp).
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
  ///
  /// A usage whose rule disappeared is dropped from the list (the store prunes
  /// the row on the next range save); a locked range stays listed but marked, so
  /// the sheet can grey it out instead of hiding it.
  Future<List<VisibleRangeWriteBackTarget>> loadAppliedTargets() async {
    final store = _requireStore();
    final usages = await store.loadUsages();
    if (usages.isEmpty) return const [];
    final owners = {for (final target in await loadPinTargets()) target.rangeId: target};
    final ranges = <String, VisibleRange?>{};
    final result = <VisibleRangeWriteBackTarget>[];
    for (final usage in usages) {
      final range = ranges[usage.rangeId] ??= await _loadRangeById(usage.rangeId);
      if (range == null) continue;
      final rule = usage.isBase ? null : range.ruleById(usage.targetId);
      if (!usage.isBase && rule == null) continue;
      final owner = owners[usage.rangeId];
      result.add(
        VisibleRangeWriteBackTarget(
          usageId: usage.id,
          rangeId: usage.rangeId,
          targetId: usage.targetId,
          kind: usage.kind,
          isGallery: usage.rangeId == gallery.id,
          number: owner?.number ?? 0,
          ownerName: owner?.name ?? '',
          label: usage.isBase ? range.baseName : rule!.label,
          filters: usage.isBase ? range.baseFilters : rule!.filters,
          locked: !_canWrite(range),
        ),
      );
    }
    return result;
  }

  /// Writes [filters] over the selected remembered targets.
  ///
  /// A rule keeps its name, kind and position; a base only changes the range it
  /// belongs to, never the shared preset catalog. Locked ranges and rules that
  /// disappeared are skipped and counted.
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
        if (usage.isBase) {
          next = next.copyWith(basePresetId: '', baseName: baseName.trim(), baseFilters: filters);
        } else {
          final rule = next.ruleById(usage.targetId);
          if (rule == null) {
            skipped++;
            continue;
          }
          next = next.copyWith(
            rules: [
              for (final candidate in next.rules)
                if (candidate.id == rule.id) candidate.copyWith(filters: filters) else candidate,
            ],
          );
        }
        written++;
      }
      if (next == range) continue;
      await _saveRange(next.copyWith(updatedAt: _now));
    }
    if (written > 0) notifyListeners();
    return VisibleRangeWriteBackResult(written: written, skipped: skipped);
  }

  /// Loads a range by id from whichever surface owns it.
  Future<VisibleRange?> _loadRangeById(String rangeId) async {
    if (rangeId == gallery.id) return gallery;
    return targetSource?.loadRange(rangeId);
  }

  /// Persists a range back to its owner, keeping the in-memory gallery in sync.
  Future<void> _saveRange(VisibleRange range) async {
    if (range.id == gallery.id) {
      await _requireStore().saveRange(range);
      _gallery = range;
    } else {
      await targetSource!.saveRange(range);
    }
  }

  /// A locked range refuses writes unless its frozen permissions allow editing,
  /// the same gate the page and the pin targets use.
  static bool _canWrite(VisibleRange range) => !range.locked || range.permissions.edit;

  // lock

  /// Locks the range with [permissions]. Quick lock passes the last preset;
  /// detailed lock passes the edited permissions.
  Future<void> lock({required VisibleRangePermissions permissions}) async {
    // Remember the closest named preset so the quick lock repeats the user's
    // choice; a custom combination falls back to read-only.
    _lastLockPreset = VisibleRangeLockPreset.values.firstWhere(
      (preset) => VisibleRangePermissions.of(preset) == permissions,
      orElse: () => VisibleRangeLockPreset.readOnly,
    );
    await _requireStore().writeState(VisibleRangeStore.keyLastLockPreset, _lastLockPreset.name);
    await _updateGallery((range) => range.copyWith(locked: true, permissions: permissions));
  }

  /// Quick lock: repeats the last permissions preset, then remembers a new one.
  Future<void> lockWithPreset(VisibleRangeLockPreset preset) => lock(permissions: VisibleRangePermissions.of(preset));

  Future<void> unlock() async {
    // Unlocking drops the frozen permissions, so the next quick lock starts from
    // the remembered preset rather than a stale editable state.
    await _updateGallery((range) => range.copyWith(locked: false, permissions: VisibleRangePermissions.readOnly));
  }

  // helpers

  Future<void> _updateGallery(VisibleRange Function(VisibleRange range) transform) async {
    final store = _requireStore();
    final next = transform(gallery).copyWith(updatedAt: _now);
    await store.saveRange(next);
    _gallery = next;
    notifyListeners();
  }

  void _ensureEditable() {
    final range = gallery;
    if (!range.locked) return;
    if (range.permissions.edit) return;
    throw StateError('visible range is locked');
  }

  VisibleRangeStore _requireStore() {
    final store = _store;
    if (store == null) throw StateError('visibleRangeController is not initialized');
    return store;
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Monotonic suffix for generated ids.
  ///
  /// Rules and presets can be created twice in the same millisecond (a test, a
  /// two-group pin, or two quick taps). A timestamp alone then yields duplicate
  /// ids, and a later write-back would update the wrong record.
  int _idSequence = 0;

  String _newId(String prefix) => '$prefix.$_now.${_idSequence++}';
}

/// The app-wide controller (the same singleton style as `vaults`).
final VisibleRangeController visibleRangeController = VisibleRangeController();
