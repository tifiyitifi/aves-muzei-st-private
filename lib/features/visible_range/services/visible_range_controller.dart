import 'dart:async';

import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/visible_range/data/default_presets.dart';
import 'package:aves/features/visible_range/db/visible_range_store.dart';
import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

const String visibleRangeLogKey = 'log.visible_range';

/// Channels this feature owns, opened in debug builds by `Log.init`.
const List<String> visibleRangeDebugLogKeys = [visibleRangeLogKey];

const AreaKeyLog _log = AreaKeyLog(visibleRangeLogKey);

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

  new({this.injectedDatabase, Future<List<VisibleRangePresetDefinition>> Function()? presetLoader})
      : presetLoader = presetLoader ?? loadVisibleRangePresetDefinitions;

  VisibleRangeStore? _store;
  VisibleRange? _gallery;
  List<VisibleRangePreset> _presets = const [];
  List<VisibleRangeSession> _sessions = const [];
  String? _openSessionId;
  VisibleRangeLockPreset _lastLockPreset = VisibleRangeLockPreset.readOnly;
  Future<void>? _initFuture;
  bool _initialized = false;

  bool get initialized => _initialized;

  VisibleRange get gallery => _gallery ?? VisibleRange.emptyGallery();

  List<VisibleRangePreset> get presets => _presets;

  /// Sessions recorded since the last save. Any save clears them.
  List<VisibleRangeSession> get sessions => _sessions;

  /// The filter resolved from the current gallery range, or null for 「不限」.
  CollectionFilter? get galleryFilter => gallery.resolve();

  /// Whether the current gallery browsing is restricted.
  bool get galleryRestricted => gallery.isRestricted;

  bool get locked => gallery.locked;

  /// Whether the current range accepts mutations from this page.
  bool get canEdit => !gallery.locked || gallery.permissions.edit;

  /// Permissions preset the quick lock reuses.
  VisibleRangeLockPreset get lastLockPreset => _lastLockPreset;

  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    final db = injectedDatabase ?? await getIt<AppDatabaseProvider>().open();
    final store = VisibleRangeStore(db);
    _store = store;
    try {
      await _seedBuiltinPresetsOnce(store);
      _presets = await store.loadPresets();
      _gallery = await store.loadRange(scope: VisibleRangeScope.gallery, ownerId: VisibleRange.galleryOwnerId) ?? VisibleRange.emptyGallery(now: _now);
      _sessions = await store.loadSessions(rangeId: _gallery!.id);
      final lastLockPreset = await store.readState(VisibleRangeStore.keyLastLockPreset);
      _lastLockPreset = VisibleRangeLockPreset.values.firstWhere(
        (v) => v.name == lastLockPreset,
        orElse: () => VisibleRangeLockPreset.readOnly,
      );
      _initialized = true;
    } catch (error, stack) {
      // A broken range store must never hide the library: fall back to 「不限」.
      _log.e('failed to load visible ranges, falling back to unrestricted', error, stack);
      _gallery = VisibleRange.emptyGallery(now: _now);
      _initialized = true;
    }
    notifyListeners();
  }

  /// Seeds the built-in base presets exactly once. A user deleting one keeps it
  /// deleted until "重新加入默认限制" adds it back.
  Future<void> _seedBuiltinPresetsOnce(VisibleRangeStore store) async {
    final seeded = await store.readState(VisibleRangeStore.keySeeded);
    if (seeded == '1') return;
    final definitions = await presetLoader();
    // An empty bundle must not burn the one-time marker: the next start with a
    // readable asset still has to seed.
    if (definitions.isEmpty) return;
    for (var i = 0; i < definitions.length; i++) {
      final definition = definitions[i];
      await store.savePreset(
        VisibleRangePreset(
          id: definition.id,
          name: definition.nameKey,
          filters: definition.filters,
          builtin: true,
          position: i,
        ),
      );
    }
    await store.writeState(VisibleRangeStore.keySeeded, '1');
  }

  // presets

  /// Re-adds the bundled presets, skipping ids and filter fingerprints that are
  /// already present. Returns how many were added and skipped.
  Future<({int added, int skipped})> reAddDefaultPresets() async {
    final store = _requireStore();
    if (gallery.locked) return (added: 0, skipped: 0);
    final definitions = await presetLoader();
    final existingIds = _presets.map((v) => v.id).toSet();
    final existingFingerprints = _presets.map((v) => v.fingerprint).toSet();
    var added = 0;
    var skipped = 0;
    var position = _presets.length;
    for (final definition in definitions) {
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
    notifyListeners();
    return (added: added, skipped: skipped);
  }

  Future<void> saveBasePreset({required String name, required Set<CollectionFilter> filters}) async {
    _ensureEditable();
    final store = _requireStore();
    final preset = VisibleRangePreset(
      id: 'user.$_now',
      name: name,
      filters: filters,
      position: _presets.length,
    );
    await store.savePreset(preset);
    _presets = await store.loadPresets();
    notifyListeners();
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
      id: 'rule.$_now.${range.rules.length}',
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

  // sessions

  /// Starts a session for activating [rule] to the media set.
  ///
  /// [resultingFilters] are the filters the media set actually opened with, so
  /// the delta write-back only accounts for what this activation added.
  Future<VisibleRangeSession> beginActivation({
    required VisibleRangeRule rule,
    required VisibleRangeActivationMode mode,
    required Set<CollectionFilter> resultingFilters,
  }) async {
    // An activation is a new session; it never retroactively rewrites the one
    // before it (that one is closed when its media set is popped).
    _openSessionId = null;
    final session = VisibleRangeSession(
      id: 'session.$_now',
      rangeId: gallery.id,
      ruleId: rule.id,
      kind: rule.kind,
      mode: mode,
      initialFilters: resultingFilters,
      finalFilters: resultingFilters,
      createdAt: _now,
    );
    await _requireStore().saveSession(session);
    _openSessionId = session.id;
    _sessions = [..._sessions, session];
    notifyListeners();
    return session;
  }

  /// Snapshots the media set when the user leaves it. Only the open session is
  /// updated; older sessions keep the final filters they were closed with.
  Future<void> closeOpenSession(Set<CollectionFilter> finalFilters) async {
    final id = _openSessionId;
    if (id == null) return;
    _openSessionId = null;
    final session = _sessions.firstWhereOrNull((v) => v.id == id);
    if (session == null) return;
    final updated = session.withFinal(finalFilters);
    await _requireStore().saveSession(updated);
    _sessions = [for (final s in _sessions) s.id == id ? updated : s];
    notifyListeners();
  }

  /// Writes a session's added/removed filters back to its source rule, then
  /// clears every session (a save always clears them).
  Future<VisibleRangeRule?> writeBackSession(String sessionId) async {
    final session = _sessions.firstWhereOrNull((v) => v.id == sessionId);
    if (session == null) return null;
    final rule = gallery.ruleById(session.ruleId);
    if (rule != null) {
      // The lock freezes rule edits, but a write-back is the save the user
      // explicitly chose; it still respects the lock's edit permission.
      if (gallery.locked && !gallery.permissions.edit) return null;
      await updateRule(rule.applyDelta(added: session.added, removed: session.removed));
    }
    await clearSessions();
    return rule == null ? null : gallery.ruleById(rule.id);
  }

  /// Clears every session record. Called by any save, chosen write-back or not.
  Future<void> clearSessions() async {
    _openSessionId = null;
    if (_sessions.isEmpty) return;
    await _requireStore().clearSessions();
    _sessions = const [];
    notifyListeners();
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
}

/// The app-wide controller (the same singleton style as `vaults`).
final VisibleRangeController visibleRangeController = VisibleRangeController();
