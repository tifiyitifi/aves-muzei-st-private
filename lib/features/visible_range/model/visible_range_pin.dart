import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One place the current filters can be pinned to.
///
/// [number] is the badge shown in the target grid: `0` is the gallery's single
/// visible range, `1..n` are wallpaper groups. The list is resolved per open, so
/// a group added a moment ago appears without a restart.
@immutable
class VisibleRangePinTarget extends Equatable {
  final String rangeId;
  final int number;

  /// Group name; empty for the gallery, which is labelled from ARB.
  final String name;
  final bool isGallery;

  /// The target refuses edits, so the grid greys it out.
  final bool locked;

  const new({
    required this.rangeId,
    required this.number,
    required this.name,
    required this.isGallery,
    this.locked = false,
  });

  VisibleRangePinTarget copyWith({bool? locked}) => VisibleRangePinTarget(
        rangeId: rangeId,
        number: number,
        name: name,
        isGallery: isGallery,
        locked: locked ?? this.locked,
      );

  @override
  List<Object?> get props => [rangeId, number, name, isGallery, locked];
}

/// What the pin sheet asks for: one filter set, one name/description, and the
/// cross product of the chosen groups and targets.
@immutable
class VisibleRangePinRequest extends Equatable {
  final Set<CollectionFilter> filters;
  final String name;
  final String description;
  final Set<VisibleRangeCandidateKind> kinds;
  final Set<String> targetRangeIds;

  const new({
    required this.filters,
    required this.name,
    required this.description,
    required this.kinds,
    required this.targetRangeIds,
  });

  bool get isEmpty => filters.isEmpty || kinds.isEmpty || targetRangeIds.isEmpty;

  @override
  List<Object?> get props => [filters, name, description, kinds, targetRangeIds];
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
