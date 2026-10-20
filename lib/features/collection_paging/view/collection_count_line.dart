import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The permanent count line under a collection's title.
///
/// Always carries the denominator: a narrowed view reads `matched / library`,
/// and a view that is the whole library reads its total alone. This is what
/// makes the paged engine's partial states legible — during the first import
/// the app bar says how much is written, and afterwards it says how much the
/// view keeps out of how much there is.
class CollectionCountLine extends StatelessWidget {
  final CollectionLens collection;

  const new({
    super.key,
    required this.collection,
  });

  @override
  Widget build(BuildContext context) {
    final lens = collection is PagedCollectionLens ? collection as PagedCollectionLens : null;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // The lens notifies on window loads and reloads, so the pair stays current
    // without a second source of truth.
    return AnimatedBuilder(
      animation: collection,
      builder: (context, child) {
        final count = collection.entryCount;
        final total = lens?.libraryEntryCount ?? count;
        final text = count == total ? l10n.itemCount(count) : l10n.collectionCountOfTotal(count, total);
        return Text(
          text,
          softWrap: false,
          overflow: .fade,
          maxLines: 1,
          style: theme.textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.disable('smcp')]),
        );
      },
    );
  }
}
