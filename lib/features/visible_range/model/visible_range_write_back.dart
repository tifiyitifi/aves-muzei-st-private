import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One remembered target, resolved for the pin sheet's write-back list.
///
/// It carries the owner (gallery or wallpaper group) and the raw label of the
/// rule or base, so the sheet localizes both and the controller stays free of
/// presentation. [locked] is already the "cannot write" verdict.
@immutable
class VisibleRangeWriteBackTarget extends Equatable {
  /// Usage id, the write-back selection key.
  final String usageId;
  final String rangeId;
  final String targetId;
  final VisibleRangeCandidateKind kind;
  final bool isGallery;

  /// Group number, or 0 for the gallery.
  final int number;

  /// Group name as stored (an ARB key while bundled); empty for the gallery.
  final String ownerName;

  /// Rule label as stored (an ARB key while bundled) or the range's base name.
  final String label;

  /// The conditions behind the target, used to label an unnamed rule.
  final Set<CollectionFilter> filters;
  final bool locked;

  const new({
    required this.usageId,
    required this.rangeId,
    required this.targetId,
    required this.kind,
    required this.isGallery,
    required this.number,
    required this.ownerName,
    required this.label,
    this.filters = const {},
    required this.locked,
  });

  bool get isBase => kind == VisibleRangeCandidateKind.base;

  @override
  List<Object?> get props => [usageId, rangeId, targetId, kind, isGallery, number, ownerName, label, filters, locked];
}

/// Outcome of a write-back: how many targets took the filters and how many were
/// skipped because their range is locked or the rule no longer exists.
@immutable
class VisibleRangeWriteBackResult extends Equatable {
  final int written;
  final int skipped;

  const new({required this.written, required this.skipped});

  @override
  List<Object?> get props => [written, skipped];
}
