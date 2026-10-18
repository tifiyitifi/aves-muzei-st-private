import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Selects the whole view, bounded on a windowed collection.
///
/// The legacy lens holds every entry, so it selects them all. A windowed one
/// cannot: the selection is an in-memory set while the scope may be a million
/// rows, so it takes [PagedCollectionLens.selectAllLimit] rows at most. When
/// that truncated the selection the user is warned, because a bulk action must
/// never run on a silently partial set.
Future<void> selectAllInCollection(BuildContext context, CollectionLens collection) async {
  final selection = context.read<Selection<AvesEntry>>();
  if (collection is! PagedCollectionLens || !collection.pagedActive) {
    selection.addToSelection(collection.sortedEntries);
    return;
  }
  final items = await collection.selectAllItems();
  selection.addToSelection(items);
  final total = collection.entryCount;
  if (!context.mounted || total <= items.length) return;
  final message = context.l10n.collectionSelectAllCapped(items.length, total);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}
