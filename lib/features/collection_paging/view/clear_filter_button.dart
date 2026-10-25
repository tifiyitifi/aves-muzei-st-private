import 'package:aves/features/collection_paging/view/filter_policy_scope.dart';
import 'package:aves/model/filters/trash.dart';
import 'package:aves/model/query.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Empties the view's filters, putting the whole library back on screen.
///
/// It closes the filter row instead of floating over the grid: the chips keep
/// the flow and alignment they had, and the action sits where the filters are
/// read. The live query is not a chip, so clearing the query bar's text is what
/// drops it — that bar's own listener removes the filter.
///
/// Filters the view marks as locked ([FilterPolicyScope]) are not user choices:
/// clearing drops everything else and keeps them, so the view still means what
/// it says.
class ClearFilterButton extends StatelessWidget {
  final CollectionLens collection;

  const new({
    super.key,
    required this.collection,
  });

  @override
  Widget build(BuildContext context) {
    final policy = FilterPolicyScope.maybeOf(context);
    return IconButton(
      // key is expected by test driver
      key: const Key('clear-filter-button'),
      icon: const Icon(AIcons.clear),
      tooltip: context.l10n.collectionActionClearFilters,
      onPressed: () {
        context.read<Query?>()?.queryNotifier.value = '';
        // The bin is a scope of its own, not a filter to clear: only the trash
        // marker survives. Locked filters are the view's own constraints.
        collection.setFilters(
          collection.filters.where((filter) => filter is TrashFilter || (policy?.isLocked(filter) ?? false)).toSet(),
        );
      },
    );
  }
}
