import 'dart:convert';

import 'package:aves/model/filters/container/set_and.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Where a range is applied: the gallery browsing surface, or one wallpaper
/// group's media set.
enum VisibleRangeScope {
  gallery,
  wallpaper;

  static VisibleRangeScope parse(String? value) => VisibleRangeScope.values.firstWhere((v) => v.name == value, orElse: () => gallery);
}

/// Group evaluation order, inherited from the old scenario `chipGroupFactor`.
///
/// It decides both the evaluation and how the supplement section is labelled:
/// - [intersectFirst]: `(base AND restrictions) OR supplements`; supplements can
///   reach outside the base, hence 「范围外补充」.
/// - [unionFirst]: `(base OR supplements) AND restrictions`; supplements are
///   then narrowed by the restrictions, hence 「限制外补充」.
enum VisibleRangeOrder {
  intersectFirst,
  unionFirst;

  static VisibleRangeOrder parse(String? value) => VisibleRangeOrder.values.firstWhere((v) => v.name == value, orElse: () => intersectFirst);

  bool get isIntersectFirst => this == intersectFirst;
}

/// The three groups a rule can belong to. Base ranges are a single filter set,
/// so a rule is only ever a restriction or a supplement.
enum VisibleRangeRuleKind {
  restriction,
  supplement;

  static VisibleRangeRuleKind parse(String? value) => VisibleRangeRuleKind.values.firstWhere((v) => v.name == value, orElse: () => restriction);
}

/// How an "activate to media set" session was started.
enum VisibleRangeActivationMode {
  override,
  append;

  static VisibleRangeActivationMode parse(String? value) => VisibleRangeActivationMode.values.firstWhere((v) => v.name == value, orElse: () => override);
}

/// Preset lock behaviour. The lock is casual protection inside Aves, never a
/// security boundary.
enum VisibleRangeLockPreset {
  readOnly,
  manageable,
  full,
}

/// Permissions frozen while a visible range is locked.
///
/// Defaults mirror the product rule: read-only with sharing allowed.
@immutable
class VisibleRangePermissions extends Equatable {
  final bool share;
  final bool delete;
  final bool edit;
  final bool move;
  final bool rename;
  final bool hide;
  final bool vault;
  final bool trash;
  final bool metadata;

  const new({
    this.share = true,
    this.delete = false,
    this.edit = false,
    this.move = false,
    this.rename = false,
    this.hide = false,
    this.vault = false,
    this.trash = false,
    this.metadata = false,
  });

  static const readOnly = VisibleRangePermissions();

  static const manageable = VisibleRangePermissions(
    delete: true,
    edit: true,
    move: true,
    rename: true,
    hide: true,
    trash: true,
    metadata: true,
  );

  static const full = VisibleRangePermissions(
    delete: true,
    edit: true,
    move: true,
    rename: true,
    hide: true,
    vault: true,
    trash: true,
    metadata: true,
  );

  VisibleRangePresetValues get presetValues => (share: share, delete: delete, edit: edit, move: move, rename: rename, hide: hide, vault: vault, trash: trash, metadata: metadata);

  static VisibleRangePermissions of(VisibleRangeLockPreset preset) => switch (preset) {
        VisibleRangeLockPreset.readOnly => readOnly,
        VisibleRangeLockPreset.manageable => manageable,
        VisibleRangeLockPreset.full => full,
      };

  @override
  List<Object?> get props => [share, delete, edit, move, rename, hide, vault, trash, metadata];

  Map<String, Object?> toMap() => {
        'share': share,
        'delete': delete,
        'edit': edit,
        'move': move,
        'rename': rename,
        'hide': hide,
        'vault': vault,
        'trash': trash,
        'metadata': metadata,
      };

  static VisibleRangePermissions? fromMap(Object? json) {
    if (json is! Map) return null;
    bool read(String key, bool fallback) => json[key] is bool ? json[key] as bool : fallback;
    return VisibleRangePermissions(
      share: read('share', true),
      delete: read('delete', false),
      edit: read('edit', false),
      move: read('move', false),
      rename: read('rename', false),
      hide: read('hide', false),
      vault: read('vault', false),
      trash: read('trash', false),
      metadata: read('metadata', false),
    );
  }
}

typedef VisibleRangePresetValues = ({
  bool share,
  bool delete,
  bool edit,
  bool move,
  bool rename,
  bool hide,
  bool vault,
  bool trash,
  bool metadata,
});

/// One AND-ed rule inside a range. [kind] places it in the restriction (AND) or
/// supplement (OR) section; [active] is the chip toggle.
@immutable
class VisibleRangeRule extends Equatable {
  final String id;
  final String rangeId;
  final VisibleRangeRuleKind kind;
  final int position;
  final String label;

  /// Free-form user note shown under the label, e.g. when and from what the rule
  /// was pinned. Never localized here: it is user text.
  final String description;
  final Set<CollectionFilter> filters;
  final bool active;

  const new({
    required this.id,
    required this.rangeId,
    required this.kind,
    this.position = 0,
    this.label = '',
    this.description = '',
    this.filters = const {},
    this.active = true,
  });

  bool get isEmpty => filters.isEmpty;

  String get effectiveLabel {
    if (label.isNotEmpty) return label;
    final names = filters.map((v) => v.universalLabel).where((v) => v.isNotEmpty).toList()..sort();
    if (names.isEmpty) return '';
    return names.join(' · ');
  }

  VisibleRangeRule copyWith({
    VisibleRangeRuleKind? kind,
    int? position,
    String? label,
    String? description,
    Set<CollectionFilter>? filters,
    bool? active,
  }) {
    return VisibleRangeRule(
      id: id,
      rangeId: rangeId,
      kind: kind ?? this.kind,
      position: position ?? this.position,
      label: label ?? this.label,
      description: description ?? this.description,
      filters: filters ?? this.filters,
      active: active ?? this.active,
    );
  }

  /// Applies a session delta: only the filters the user actually added/removed
  /// are written back, so two sessions of the same range never overwrite each
  /// other's unrelated edits.
  VisibleRangeRule applyDelta({required Set<CollectionFilter> added, required Set<CollectionFilter> removed}) {
    final next = filters.whereNot(removed.contains).toSet()..addAll(added);
    return copyWith(filters: next);
  }

  @override
  List<Object?> get props => [id, rangeId, kind, position, label, description, filters, active];
}

/// A base-range preset (built-in or user-saved). Built-in presets are read-only.
@immutable
class VisibleRangePreset extends Equatable {
  final String id;
  final String name;
  final String description;
  final Set<CollectionFilter> filters;
  final bool builtin;
  final int position;

  const new({
    required this.id,
    required this.name,
    this.description = '',
    this.filters = const {},
    this.builtin = false,
    this.position = 0,
  });

  /// Filters fingerprint, used by "重新加入默认限制" to skip duplicates.
  String get fingerprint => filterFingerprint(filters);

  VisibleRangePreset copyWith({
    String? name,
    String? description,
    Set<CollectionFilter>? filters,
    bool? builtin,
    int? position,
  }) {
    return VisibleRangePreset(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      filters: filters ?? this.filters,
      builtin: builtin ?? this.builtin,
      position: position ?? this.position,
    );
  }

  @override
  List<Object?> get props => [id, name, description, filters, builtin, position];
}

/// One "activate to media set" record.
@immutable
class VisibleRangeSession extends Equatable {
  final String id;
  final String rangeId;
  final String ruleId;
  final VisibleRangeRuleKind kind;
  final VisibleRangeActivationMode mode;
  final Set<CollectionFilter> initialFilters;
  final Set<CollectionFilter> finalFilters;
  final int createdAt;

  const new({
    required this.id,
    required this.rangeId,
    required this.ruleId,
    required this.kind,
    required this.mode,
    required this.initialFilters,
    required this.finalFilters,
    required this.createdAt,
  });

  Set<CollectionFilter> get added => finalFilters.whereNot(initialFilters.contains).toSet();

  Set<CollectionFilter> get removed => initialFilters.whereNot(finalFilters.contains).toSet();

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

  VisibleRangeSession withFinal(Set<CollectionFilter> filters) => VisibleRangeSession(
        id: id,
        rangeId: rangeId,
        ruleId: ruleId,
        kind: kind,
        mode: mode,
        initialFilters: initialFilters,
        finalFilters: filters,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, rangeId, ruleId, kind, mode, initialFilters, finalFilters, createdAt];
}

/// A complete visible range: base + rule sets + order.
@immutable
class VisibleRange extends Equatable {
  final String id;
  final VisibleRangeScope scope;
  final String ownerId;
  final String baseName;
  final String basePresetId;
  final Set<CollectionFilter> baseFilters;
  final List<VisibleRangeRule> rules;
  final VisibleRangeOrder order;
  final bool locked;
  final VisibleRangePermissions permissions;
  final int createdAt;
  final int updatedAt;

  const new({
    required this.id,
    required this.scope,
    required this.ownerId,
    this.baseName = '',
    this.basePresetId = '',
    this.baseFilters = const {},
    this.rules = const [],
    this.order = VisibleRangeOrder.intersectFirst,
    this.locked = false,
    this.permissions = VisibleRangePermissions.readOnly,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  /// 「不限」: no base filter set selected.
  bool get isBaseUnrestricted => baseFilters.isEmpty;

  /// Only the base and the active restrictions decide "受限"; supplements never
  /// do, because a supplement can only add back what the base already allowed
  /// when the base is unrestricted.
  bool get isRestricted {
    if (baseFilters.isNotEmpty) return true;
    return rules.any((rule) => rule.active && rule.kind == VisibleRangeRuleKind.restriction && rule.filters.isNotEmpty);
  }

  /// True when nothing would be filtered at all.
  bool get isUnrestricted => !isRestricted && rules.every((rule) => !rule.active || rule.filters.isEmpty);

  List<VisibleRangeRule> activeRulesOf(VisibleRangeRuleKind kind) =>
      rules.where((rule) => rule.active && rule.kind == kind && rule.filters.isNotEmpty).toList()..sort((a, b) => a.position.compareTo(b.position));

  List<VisibleRangeRule> rulesOf(VisibleRangeRuleKind kind) => rules.where((rule) => rule.kind == kind).toList()..sort((a, b) => a.position.compareTo(b.position));

  VisibleRangeRule? ruleById(String id) => rules.firstWhereOrNull((rule) => rule.id == id);

  /// The base alone, as a filter (null for 「不限」).
  CollectionFilter? get resolvedBase => _and(baseFilters);

  /// The first group applied on top of the base, following [order].
  ///
  /// The page shows this step's cumulative count, so it must mirror the exact
  /// first half of [resolve] without the final group.
  CollectionFilter? get resolvedIntermediate {
    final restrictions = [for (final rule in activeRulesOf(VisibleRangeRuleKind.restriction)) ...rule.filters];
    final supplements = [for (final rule in activeRulesOf(VisibleRangeRuleKind.supplement)) ...rule.filters];
    if (order.isIntersectFirst) return _and({...baseFilters, ...restrictions});
    // Union-first: an unrestricted base excepts the whole union, so there is no
    // intermediate narrowing to show.
    if (baseFilters.isEmpty) return null;
    return supplements.isEmpty ? _or(baseFilters) : _or({...baseFilters, ...supplements});
  }

  /// Resolves the range to one filter tree, or null when it filters nothing.
  ///
  /// Both orders are built from the same pieces so an unrestricted base is a
  /// no-op in either direction:
  /// - intersect-first: `(base AND restrictions) OR supplements`
  /// - union-first: `(base OR supplements) AND restrictions`
  CollectionFilter? resolve() {
    final restrictions = [for (final rule in activeRulesOf(VisibleRangeRuleKind.restriction)) ...rule.filters];
    final supplements = [for (final rule in activeRulesOf(VisibleRangeRuleKind.supplement)) ...rule.filters];

    if (order.isIntersectFirst) {
      final conjunction = _and({...baseFilters, ...restrictions});
      if (supplements.isEmpty) return conjunction;
      return _or({?conjunction, ...supplements});
    }

    // An empty base means 「不限」, i.e. everything: OR-ing supplements cannot add
    // anything, so the union step collapses to the restrictions alone.
    final disjunction = baseFilters.isEmpty ? null : (supplements.isEmpty ? _or(baseFilters) : _or({...baseFilters, ...supplements}));
    final conjunction = _and({?disjunction, ...restrictions});
    return conjunction;
  }

  static CollectionFilter? _and(Set<CollectionFilter> filters) {
    if (filters.isEmpty) return null;
    if (filters.length == 1) return filters.first;
    return SetAndFilter(filters);
  }

  static CollectionFilter? _or(Set<CollectionFilter> filters) {
    if (filters.isEmpty) return null;
    if (filters.length == 1) return filters.first;
    return SetOrFilter(filters);
  }

  VisibleRange copyWith({
    String? baseName,
    String? basePresetId,
    Set<CollectionFilter>? baseFilters,
    List<VisibleRangeRule>? rules,
    VisibleRangeOrder? order,
    bool? locked,
    VisibleRangePermissions? permissions,
    int? updatedAt,
  }) {
    return VisibleRange(
      id: id,
      scope: scope,
      ownerId: ownerId,
      baseName: baseName ?? this.baseName,
      basePresetId: basePresetId ?? this.basePresetId,
      baseFilters: baseFilters ?? this.baseFilters,
      rules: rules ?? this.rules,
      order: order ?? this.order,
      locked: locked ?? this.locked,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// A new, empty gallery range. Not persisted until the user changes something.
  static VisibleRange emptyGallery({String id = galleryRangeId, int now = 0}) => VisibleRange(
        id: id,
        scope: VisibleRangeScope.gallery,
        ownerId: galleryOwnerId,
        createdAt: now,
        updatedAt: now,
      );

  static const galleryOwnerId = 'gallery';
  static const galleryRangeId = 'gallery';

  @override
  List<Object?> get props => [id, scope, ownerId, baseName, basePresetId, baseFilters, rules, order, locked, permissions, createdAt, updatedAt];
}

/// Stable fingerprint of a filter set, used to dedupe presets/rules.
String filterFingerprint(Iterable<CollectionFilter> filters) {
  final keys = filters.map((filter) => filter.key).toList()..sort();
  return keys.join('\u0000');
}

/// Id of a built-in rule materialized from the bundled defaults.
String visibleRangeBuiltinRuleId(String definitionId) => 'builtin.rule.$definitionId';

/// Whether a rule is a materialized default rather than a user rule.
bool isVisibleRangeBuiltinRule(String id) => id.startsWith('builtin.rule.');

/// JSON codec for filter collections stored in text columns.
abstract final class VisibleRangeFilterCodec {
  static String encode(Iterable<CollectionFilter> filters) => jsonEncode(filters.map((v) => v.toJsonMap()).toList());

  static Set<CollectionFilter> decode(Object? raw) {
    final source = raw is String ? raw : (raw == null ? '' : jsonEncode(raw));
    if (source.isEmpty) return {};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return {};
      return decoded.map(CollectionFilter.fromJson).nonNulls.toSet();
    } catch (error) {
      // A corrupt row must never crash a browse: an unreadable range reads as
      // 「不限」, which is the same direction the feature already treats an empty
      // base.
      debugPrint('failed to decode visible range filters: $error');
      return {};
    }
  }
}
