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

/// What a stored range row is.
///
/// A [group] is one mutually exclusive visibility group: exactly one gallery
/// group is current, and a wallpaper group belongs to one `WallpaperGroup`.
/// An [outside] row is the scope-wide pool shared by every group of its scope;
/// only the gallery has one.
enum VisibleRangeGroupKind {
  group,
  outside;

  static VisibleRangeGroupKind parse(String? value) => VisibleRangeGroupKind.values.firstWhere((v) => v.name == value, orElse: () => group);
}

/// Group evaluation order, inherited from the old scenario `chipGroupFactor`.
///
/// It decides how the group's own conditions combine:
/// - [intersectFirst]: `(sources AND restrictions) OR supplements`; supplements
///   can reach outside the sources.
/// - [unionFirst]: `(sources OR supplements) AND restrictions`; supplements are
///   then narrowed by the restrictions.
///
/// The scope-wide outside layer always applies last and is not affected by this
/// order.
enum VisibleRangeOrder {
  intersectFirst,
  unionFirst;

  static VisibleRangeOrder parse(String? value) => VisibleRangeOrder.values.firstWhere((v) => v.name == value, orElse: () => intersectFirst);

  bool get isIntersectFirst => this == intersectFirst;
}

/// The three roles a condition can play inside a group.
///
/// [source] conditions are OR-ed with each other and define what the group can
/// show; [restriction] conditions are AND-ed on top; [supplement] conditions are
/// OR-ed back in. A rule's own filters are always AND-ed together.
///
/// The outside pool only supports the last two: it has no source role, because a
/// shared source would widen every group at once.
enum VisibleRangeRuleKind {
  source,
  restriction,
  supplement;

  static VisibleRangeRuleKind parse(String? value) => VisibleRangeRuleKind.values.firstWhere((v) => v.name == value, orElse: () => restriction);

  /// The roles the scope-wide outside pool accepts.
  static const outsideRoles = [VisibleRangeRuleKind.restriction, VisibleRangeRuleKind.supplement];

  bool get isOutsideAllowed => this != source;
}

/// How a single rule opens the media set from its editor.
///
/// [override] replaces the media set's filters, [append] adds to them. A
/// multi-selection always appends, so this mode only describes the one-rule
/// editor.
enum VisibleRangeActivationMode {
  override,
  append,
}

/// Whether a pin turns the conditions it writes on, only writes them, or lets
/// the target decide.
///
/// [auto] is the default: a condition written into a group that has no
/// conditions yet is enabled, and every other new condition is parked so the
/// user turns it on deliberately. Re-pinning an existing condition never
/// changes its state.
enum VisibleRangeInjectionMode {
  auto,
  enable,
  park;

  static VisibleRangeInjectionMode parse(String? value) => VisibleRangeInjectionMode.values.firstWhere((v) => v.name == value, orElse: () => auto);
}

/// How a pin that targets a non-empty group treats the conditions already there.
enum VisibleRangePinWriteMode {
  append,
  replace;

  static VisibleRangePinWriteMode parse(String? value) => VisibleRangePinWriteMode.values.firstWhere((v) => v.name == value, orElse: () => append);
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

/// One rule inside a range. [kind] places it in the source (OR), restriction
/// (AND) or supplement (OR) section; [active] is the gallery chip toggle.
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

  /// Which wallpaper surfaces use this condition, as a bit mask.
  ///
  /// A wallpaper group stores every condition once and keeps only this mark per
  /// surface (`1` home, `2` lock); the gallery range ignores it, because its
  /// single surface is the whole app.
  final int surfaces;

  const new({
    required this.id,
    required this.rangeId,
    required this.kind,
    this.position = 0,
    this.label = '',
    this.description = '',
    this.filters = const {},
    this.active = true,
    this.surfaces = 0,
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
    int? surfaces,
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
      surfaces: surfaces ?? this.surfaces,
    );
  }

  @override
  List<Object?> get props => [id, rangeId, kind, position, label, description, filters, active, surfaces];
}

/// A base-range preset (built-in or user-saved). Built-in presets are read-only.
///
/// Since the visibility-group refactor this table is the **group template**
/// catalog: a preset materializes a gallery group with one source condition.
/// Rows migrate into groups; the table is kept one release for rollback.
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

/// A complete visibility range: one group (or the outside pool) with its
/// source/restriction/supplement rules and order.
@immutable
class VisibleRange extends Equatable {
  final String id;
  final VisibleRangeScope scope;
  final VisibleRangeGroupKind kind;
  final String ownerId;

  /// Group name. Empty means "the scope's default label"; a value starting with
  /// `@` is an ARB key (a bundled group), anything else is user text.
  final String name;

  /// Display order inside the scope. The group number is derived from it.
  final int position;
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
    this.kind = VisibleRangeGroupKind.group,
    this.name = '',
    this.position = 0,
    this.rules = const [],
    this.order = VisibleRangeOrder.intersectFirst,
    this.locked = false,
    this.permissions = VisibleRangePermissions.readOnly,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  bool get isOutside => kind == VisibleRangeGroupKind.outside;

  /// Whether the group narrows anything on its own.
  ///
  /// Only sources and restrictions decide "restricted"; a supplement can only
  /// add back what the sources already allowed.
  bool get hasOwnRestriction => _activeFilterOf(VisibleRangeRuleKind.source) != null || _activeFilterOf(VisibleRangeRuleKind.restriction) != null;

  /// Whether the range, together with [outside], narrows browsing.
  bool isRestricted({VisibleRange? outside}) => hasOwnRestriction || (outside?.hasOwnRestriction ?? false);

  /// True when nothing would be filtered at all.
  bool isUnrestricted({VisibleRange? outside}) => !isRestricted(outside: outside);

  List<VisibleRangeRule> activeRulesOf(VisibleRangeRuleKind kind) => rules.where((rule) => rule.active && rule.kind == kind && rule.filters.isNotEmpty).toList()..sort((a, b) => a.position.compareTo(b.position));

  List<VisibleRangeRule> rulesOf(VisibleRangeRuleKind kind) => rules.where((rule) => rule.kind == kind).toList()..sort((a, b) => a.position.compareTo(b.position));

  VisibleRangeRule? ruleById(String id) => rules.firstWhereOrNull((rule) => rule.id == id);

  /// Read-only view of the legacy v18 base, which is the group's first source.
  ///
  /// The old base columns collapsed into `source` rules in v19. These views keep
  /// the migration fixtures and the pre-refactor assertions readable without
  /// reintroducing a second storage concept.
  Set<CollectionFilter> get baseFilters => rulesOf(VisibleRangeRuleKind.source).firstOrNull?.filters ?? const {};

  String get baseName => rulesOf(VisibleRangeRuleKind.source).firstOrNull?.label ?? '';

  bool get baseActive => rulesOf(VisibleRangeRuleKind.source).any((rule) => rule.active);

  int get baseSurfaces => rulesOf(VisibleRangeRuleKind.source).firstOrNull?.surfaces ?? 0;

  String get basePresetId => '';

  bool get isBaseUnrestricted => rulesOf(VisibleRangeRuleKind.source).isEmpty;

  /// The active sources, OR-ed: each rule contributes its own AND-ed filters.
  CollectionFilter? get sourceFilter => _orRules(VisibleRangeRuleKind.source);

  /// Every active restriction, AND-ed together.
  CollectionFilter? get restrictionFilter {
    final filters = [for (final rule in activeRulesOf(VisibleRangeRuleKind.restriction)) ...rule.filters];
    return _and(filters);
  }

  /// Every active supplement, OR-ed together.
  CollectionFilter? get supplementFilter {
    final filters = [for (final rule in activeRulesOf(VisibleRangeRuleKind.supplement)) ...rule.filters];
    return _or(filters);
  }

  CollectionFilter? _activeFilterOf(VisibleRangeRuleKind kind) => switch (kind) {
    VisibleRangeRuleKind.source => sourceFilter,
    VisibleRangeRuleKind.restriction => restrictionFilter,
    VisibleRangeRuleKind.supplement => supplementFilter,
  };

  /// OR over the rules of [kind], each one narrowed by its own conjunction.
  ///
  /// OR-ing the flattened filter list would turn a rule holding two filters into
  /// a union, so each rule is built first and the rules are joined afterwards.
  CollectionFilter? _orRules(VisibleRangeRuleKind kind) {
    final parts = [for (final rule in activeRulesOf(kind)) _and(rule.filters)].nonNulls.toList();
    return _or(parts);
  }

  /// The group's own result, before the outside layer.
  CollectionFilter? resolveOwn() {
    final sources = sourceFilter;
    final restrictions = restrictionFilter;
    final supplements = supplementFilter;

    if (order.isIntersectFirst) {
      final conjunction = _and([?sources, ?restrictions]);
      // An unrestricted group OR-ed with supplements is still unrestricted.
      if (conjunction == null) return null;
      return _or([conjunction, ?supplements]);
    }

    // Union-first: an unrestricted source set swallows the supplements, so the
    // union step collapses to the restrictions alone.
    final disjunction = sources == null ? null : _or([sources, ?supplements]);
    return _and([?disjunction, ?restrictions]);
  }

  /// Resolves the range to one filter tree, or null when it filters nothing.
  ///
  /// The group is evaluated with its own [order], then the scope-wide outside
  /// pool applies last: `(group AND outsideRestrictions) OR outsideSupplements`.
  /// Supplements never narrow, so an unrestricted group plus outside
  /// supplements is still unrestricted.
  CollectionFilter? resolve({VisibleRange? outside}) {
    final own = resolveOwn();
    final outsideRestriction = outside?.restrictionFilter;
    final outsideSupplement = outside?.supplementFilter;
    if (outsideRestriction == null && outsideSupplement == null) return own;
    if (own == null && outsideRestriction == null) return null;
    final narrowed = _and([?own, ?outsideRestriction]);
    if (outsideSupplement == null) return narrowed;
    return _or([?narrowed, outsideSupplement]);
  }

  static CollectionFilter? _and(Iterable<CollectionFilter> filters) {
    // A conjunction is associative, so nested positive ANDs are flattened. A
    // reversed one is a disjunction of complements and must stay intact.
    final set = <CollectionFilter>{};
    for (final filter in filters) {
      if (filter is SetAndFilter && !filter.reversed) {
        set.addAll(filter.innerFilters);
      } else {
        set.add(filter);
      }
    }
    if (set.isEmpty) return null;
    if (set.length == 1) return set.first;
    return SetAndFilter(set);
  }

  static CollectionFilter? _or(Iterable<CollectionFilter> filters) {
    final set = filters.toSet();
    if (set.isEmpty) return null;
    if (set.length == 1) return set.first;
    return SetOrFilter(set);
  }

  VisibleRange copyWith({
    VisibleRangeGroupKind? kind,
    String? name,
    int? position,
    List<VisibleRangeRule>? rules,
    VisibleRangeOrder? order,
    bool? locked,
    VisibleRangePermissions? permissions,
    int? updatedAt,
    // Legacy v18 base fields, rewritten onto the first source condition. Only
    // the migration fixtures use them; production code edits the source rules.
    String? baseName,
    String? basePresetId,
    Set<CollectionFilter>? baseFilters,
    bool? baseActive,
    int? baseSurfaces,
  }) {
    var nextRules = rules ?? this.rules;
    final touchesBase = baseName != null || basePresetId != null || baseFilters != null || baseActive != null || baseSurfaces != null;
    if (touchesBase) {
      final first = nextRules.firstWhereOrNull((rule) => rule.kind == VisibleRangeRuleKind.source) ?? rulesOf(VisibleRangeRuleKind.source).firstOrNull;
      final filters = baseFilters ?? first?.filters ?? const {};
      if (filters.isEmpty) {
        nextRules = nextRules.where((rule) => rule.kind != VisibleRangeRuleKind.source).toList();
      } else {
        final updated = VisibleRangeRule(
          id: first?.id ?? 'source.$id',
          rangeId: id,
          kind: VisibleRangeRuleKind.source,
          position: first?.position ?? 0,
          label: baseName ?? first?.label ?? '',
          description: first?.description ?? '',
          filters: filters,
          active: baseActive ?? first?.active ?? true,
          surfaces: baseSurfaces ?? first?.surfaces ?? 0,
        );
        nextRules = nextRules.any((rule) => rule.kind == VisibleRangeRuleKind.source)
            ? [for (final rule in nextRules) rule.kind == VisibleRangeRuleKind.source ? updated : rule]
            : [...nextRules, updated];
      }
    }
    return VisibleRange(
      id: id,
      scope: scope,
      kind: kind ?? this.kind,
      ownerId: ownerId,
      name: name ?? this.name,
      position: position ?? this.position,
      rules: nextRules,
      order: order ?? this.order,
      locked: locked ?? this.locked,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Builds a range from the legacy base fields.
  ///
  /// Only the pre-v19 fixtures and the migration use this; production code adds
  /// `source` rules. A non-empty base becomes one source condition so the old
  /// assertions keep meaning the same thing.
  static VisibleRange legacy({
    required String id,
    required VisibleRangeScope scope,
    required String ownerId,
    VisibleRangeGroupKind kind = VisibleRangeGroupKind.group,
    String name = '',
    int position = 0,
    String baseName = '',
    String basePresetId = '',
    Set<CollectionFilter> baseFilters = const {},
    bool baseActive = true,
    int baseSurfaces = 0,
    List<VisibleRangeRule> rules = const [],
    VisibleRangeOrder order = VisibleRangeOrder.intersectFirst,
    bool locked = false,
    VisibleRangePermissions permissions = VisibleRangePermissions.readOnly,
    int createdAt = 0,
    int updatedAt = 0,
  }) {
    return VisibleRange(
      id: id,
      scope: scope,
      kind: kind,
      ownerId: ownerId,
      name: name,
      position: position,
      rules: [
        if (baseFilters.isNotEmpty)
          VisibleRangeRule(
            id: 'source.$id',
            rangeId: id,
            kind: VisibleRangeRuleKind.source,
            label: baseName,
            filters: baseFilters,
            active: baseActive,
            surfaces: baseSurfaces,
          ),
        ...rules,
      ],
      order: order,
      locked: locked,
      permissions: permissions,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// A new, empty gallery group. Not persisted until the user changes something.
  static VisibleRange emptyGallery({String id = galleryRangeId, String name = '', int now = 0}) => VisibleRange(
    id: id,
    scope: VisibleRangeScope.gallery,
    ownerId: id,
    name: name,
    createdAt: now,
    updatedAt: now,
  );

  /// A new, empty group for [scope].
  static VisibleRange emptyGroup({required VisibleRangeScope scope, required String id, String name = '', int position = 0, String? ownerId, int now = 0}) => VisibleRange(
    id: id,
    scope: scope,
    ownerId: ownerId ?? id,
    name: name,
    position: position,
    createdAt: now,
    updatedAt: now,
  );

  /// The gallery's scope-wide outside pool.
  static VisibleRange emptyOutside({int now = 0}) => VisibleRange(
    id: galleryOutsideId,
    scope: VisibleRangeScope.gallery,
    kind: VisibleRangeGroupKind.outside,
    ownerId: galleryOutsideId,
    createdAt: now,
    updatedAt: now,
  );

  static const galleryOwnerId = 'gallery';
  static const galleryRangeId = 'gallery';
  static const galleryOutsideId = 'gallery.outside';

  @override
  List<Object?> get props => [id, scope, kind, ownerId, name, position, rules, order, locked, permissions, createdAt, updatedAt];
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

/// Id of a built-in gallery group materialized from the bundled defaults.
String visibleRangeBuiltinGroupId(String definitionId) => 'builtin.group.$definitionId';

/// Whether a group is a materialized default rather than a user group.
bool isVisibleRangeBuiltinGroup(String id) => id.startsWith('builtin.group.');

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
