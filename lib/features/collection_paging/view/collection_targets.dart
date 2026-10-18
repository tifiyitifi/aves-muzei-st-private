import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/collection_lens.dart';

/// The entries an entry-set action applies to.
///
/// Selecting: the selection. Browsing: the whole collection — except on a
/// windowed one, whose `sortedEntries` is a *lazy* list: walking it reads one
/// skeleton per position and kicks a window for each, which on a huge library
/// freezes the UI and hands the action placeholder entries. The loaded
/// neighbourhood is the target set there instead.
///
/// Actions that genuinely need the whole collection on a huge library ask the
/// engine rather than this list (the slideshow shuffles a paged copy; stats read
/// the database).
Set<AvesEntry> collectionTargetItems({
  required CollectionLens collection,
  required bool isSelecting,
  required Iterable<AvesEntry> selectedItems,
}) {
  final groupedEntries = isSelecting ? selectedItems : _browsingTargets(collection);
  return groupedEntries.expand((entry) => entry.stackedEntries ?? {entry}).toSet();
}

List<AvesEntry> _browsingTargets(CollectionLens collection) {
  if (collection is PagedCollectionLens && collection.pagedActive) {
    return collection.loadedEntries;
  }
  return collection.sortedEntries;
}
