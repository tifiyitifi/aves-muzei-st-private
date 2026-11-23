import 'package:aves/features/visible_range/model/visible_range.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A pinned media set, split into the roles a group stores.
///
/// Each entry of [sources] becomes one source condition whose filters are
/// AND-ed; the rules themselves are OR-ed, so the split is exactly the original
/// media set only when the source part is already a union.
@immutable
class VisibleRangePinSplit extends Equatable {
  final List<Set<CollectionFilter>> sources;
  final List<CollectionFilter> restrictions;
  final List<CollectionFilter> supplements;

  const new({this.sources = const [], this.restrictions = const [], this.supplements = const []});

  bool get isEmpty => sources.isEmpty && restrictions.isEmpty && supplements.isEmpty;

  /// Every filter the split carries, in a stable order.
  Set<CollectionFilter> get allFilters => {
    for (final source in sources) ...source,
    ...restrictions,
    ...supplements,
  };

  @override
  List<Object?> get props => [sources, restrictions, supplements];
}

/// Whether [filter] names a media source rather than a narrowing condition.
///
/// Albums and paths are what the group's source section is for; a union is a
/// source only when every member is, and a reversed filter never is: turning
/// "everything except X" into a positive source would invert its meaning.
bool isVisibleRangeSourceScope(CollectionFilter filter) {
  if (filter.reversed) return false;
  return switch (filter) {
    AlbumBaseFilter() || PathFilter() => true,
    SetOrFilter() => filter.innerFilters.isNotEmpty && filter.innerFilters.every(isVisibleRangeSourceScope),
    _ => false,
  };
}

/// Splits a pinned media set into group roles.
///
/// Auto mode keeps the result equivalent to the media set:
/// - a source-only union becomes one source per member (the union is preserved);
/// - any other positive source filters stay together in one source (their
///   conjunction is preserved);
/// - everything else becomes a restriction, one per filter (AND is associative).
///
/// Supplements are never produced automatically: the default injection is
/// source + restriction. [forcedRole] overrides the classification, which is
/// an explicit semantic change the user asked for.
VisibleRangePinSplit splitVisibleRangePin(Set<CollectionFilter> filters, {VisibleRangeRuleKind? forcedRole}) {
  if (filters.isEmpty) return const VisibleRangePinSplit();
  switch (forcedRole) {
    case VisibleRangeRuleKind.source:
      return VisibleRangePinSplit(sources: [filters]);
    case VisibleRangeRuleKind.restriction:
      return VisibleRangePinSplit(restrictions: filters.toList());
    case VisibleRangeRuleKind.supplement:
      return VisibleRangePinSplit(supplements: filters.toList());
    case null:
      break;
  }

  final sources = filters.where(isVisibleRangeSourceScope).toList();
  final restrictions = filters.where((filter) => !isVisibleRangeSourceScope(filter)).toList();
  if (sources.isEmpty) return VisibleRangePinSplit(restrictions: restrictions);

  final only = sources.firstOrNull;
  if (sources.length == 1 && only is SetOrFilter) {
    // A source-only union is already the OR the group stores, so each member
    // becomes its own source and the union survives.
    return VisibleRangePinSplit(
      sources: [for (final member in only.innerFilters) {member}],
      restrictions: restrictions,
    );
  }
  return VisibleRangePinSplit(sources: [sources.toSet()], restrictions: restrictions);
}
