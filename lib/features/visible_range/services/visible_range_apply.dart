import 'package:aves/features/collection_paging/view/media_set_tab.dart';
import 'package:aves/features/visible_range/model/visible_range_candidate.dart';
import 'package:aves/features/visible_range/services/visible_range_controller.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/navigation/nav_item.dart';
import 'package:flutter/widgets.dart';

/// Opens the media set with the filters of [candidates].
///
/// One selection takes one candidate; a multi-selection takes the union of their
/// filters, deduplicated. Appending is the default because the user is adding
/// conditions to what they were looking at, not replacing it; [replace] opens the
/// media set with the candidates alone, which is what a rule's "replace" action
/// means. Every applied target is remembered, so the pin sheet can later write
/// the current filters back over them.
Future<void> applyVisibleRangeCandidates(
  BuildContext context, {
  required String rangeId,
  required Iterable<VisibleRangeCandidate> candidates,
  bool replace = false,
}) async {
  final selected = candidates.where((candidate) => candidate.isApplicable).toList();
  if (selected.isEmpty) return;
  final filters = <CollectionFilter>{for (final candidate in selected) ...candidate.filters};
  final target = replace ? filters : {...?mediaSetTab.currentFilters, ...filters};
  await visibleRangeController.markAppliedTargets(rangeId: rangeId, candidates: selected);
  if (!context.mounted) return;
  await AvesNavItem(route: CollectionPage.routeName, filters: target).goTo(context, topLevel: false);
}
