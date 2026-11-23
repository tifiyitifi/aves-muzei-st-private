import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// What kind of range a pin target writes into.
enum VisibleRangePinTargetKind {
  /// One mutually exclusive gallery group.
  galleryGroup,

  /// The gallery's scope-wide outside pool, one target per role.
  outside,

  /// One wallpaper group's shared condition pool.
  wallpaperGroup,
}

/// One place the current filters can be pinned to.
///
/// [id] is the selection key: it is unique even when two targets (the outside
/// restriction and the outside supplement) write the same pool. [rangeId] is the
/// range the write lands on. [number] is the badge shown in the target grid: the
/// group number for a group, `0` for the outside pool.
@immutable
class VisibleRangePinTarget extends Equatable {
  final String id;
  final String rangeId;
  final VisibleRangePinTargetKind kind;

  /// The outside role this target writes, or null for a group.
  final VisibleRangeRuleKind? role;
  final int number;

  /// Group name; a value starting with `@` is an ARB key.
  final String name;

  /// The target refuses edits, so the grid greys it out.
  final bool locked;

  const new({
    required this.id,
    required this.rangeId,
    required this.kind,
    this.role,
    required this.number,
    this.name = '',
    this.locked = false,
  });

  bool get isGallery => kind != VisibleRangePinTargetKind.wallpaperGroup;

  bool get isOutside => kind == VisibleRangePinTargetKind.outside;

  bool get isWallpaperGroup => kind == VisibleRangePinTargetKind.wallpaperGroup;

  VisibleRangePinTarget copyWith({bool? locked}) => VisibleRangePinTarget(
    id: id,
    rangeId: rangeId,
    kind: kind,
    role: role,
    number: number,
    name: name,
    locked: locked ?? this.locked,
  );

  @override
  List<Object?> get props => [id, rangeId, kind, role, number, name, locked];
}

/// What the pin sheet asks for: one filter set, one name/description, and the
/// cross product of the chosen targets and roles.
@immutable
class VisibleRangePinRequest extends Equatable {
  final Set<CollectionFilter> filters;
  final String name;
  final String description;

  /// Target ids, not range ids: the outside pool is two targets.
  final Set<String> targetIds;
  final VisibleRangeInjectionMode injection;

  /// Forces every condition into one role instead of the automatic split.
  ///
  /// The forced roles are an explicit semantic change, so equivalence with the
  /// media set is only guaranteed for the automatic split.
  final VisibleRangeRuleKind? forcedRole;

  /// Whether a non-empty group keeps its conditions (append) or replaces them.
  final VisibleRangePinWriteMode writeMode;

  const new({
    required this.filters,
    required this.name,
    required this.description,
    required this.targetIds,
    this.injection = VisibleRangeInjectionMode.auto,
    this.forcedRole,
    this.writeMode = VisibleRangePinWriteMode.append,
  });

  bool get isEmpty => filters.isEmpty || targetIds.isEmpty;

  @override
  List<Object?> get props => [filters, name, description, targetIds, injection, forcedRole, writeMode];
}

/// Outcome of a pin: how many targets took the filters, how many were skipped
/// because they were locked or no longer registered, and how many remembered
/// targets the same confirmation wrote the filters back to.
@immutable
class VisibleRangePinResult extends Equatable {
  final int pinned;
  final int skipped;
  final int written;
  final int writeSkipped;

  const new({
    required this.pinned,
    required this.skipped,
    this.written = 0,
    this.writeSkipped = 0,
  });

  bool get hasPinned => pinned > 0;

  bool get hasWritten => written > 0;

  @override
  List<Object?> get props => [pinned, skipped, written, writeSkipped];
}
