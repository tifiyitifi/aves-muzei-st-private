import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Marks the whole view selected.
///
/// The legacy lens holds every entry, so it selects them all. A windowed one
/// cannot enumerate a million rows, so it *declares* the view marked instead: the
/// count and the scope come from the database, and only the rows the user unmarks
/// afterwards are remembered. An action then resolves the mark through its feed,
/// in bounded batches.
void selectAllInCollection(BuildContext context, CollectionLens collection) {
  final selection = context.read<Selection<AvesEntry>>();
  if (collection is PagedCollectionLens) {
    final mark = collection.newSelectionMark();
    if (mark != null) {
      selection.markAll(mark);
      return;
    }
  }
  selection.addToSelection(collection.sortedEntries);
}
