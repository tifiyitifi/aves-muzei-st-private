import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/features/collection_paging/selection/selection_mark.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/section_keys.dart';
import 'package:aves/widgets/common/grid/sections/list_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Toggles a whole section's trait on a marked view, and reports whether it did.
///
/// A windowed view cannot enumerate a section — its rows are served in windows —
/// so the header's toggle becomes one trait op over the whole section instead of
/// the rows that happen to be loaded. That is what makes "deselect this album"
/// cover the album rather than its first screen, and selecting it again exact.
///
/// False leaves the caller with the legacy loaded-rows toggle: a filter grid (a
/// different item type), a legacy (fully loaded) collection, a selection that is
/// not a mark, or a section kind with no exact trait.
bool toggleSectionTraitSelection<T>(BuildContext context, SectionKey sectionKey, String label) {
  if (T != AvesEntry) return false;
  final selection = context.read<Selection<T>>();
  // Typed as `Object?` so the mark promotes: `CollectionSelectionMark` is not
  // statically a subtype of `SelectionMark<T>` while `T` is a type variable.
  final Object? mark = selection.mark;
  if (mark is! CollectionSelectionMark) return false;
  final lens = context.read<CollectionLens>();
  if (lens is! PagedCollectionLens) return false;
  final trait = lens.sectionTrait(sectionKey);
  if (trait == null) return false;
  // The direction follows the same state the header's own button shows.
  final sectionEntries = context.read<SectionedListLayout<T>>().sections[sectionKey] ?? <T>[];
  if (selection.isSelected(sectionEntries)) {
    mark.deselectTrait(trait, label: label);
  } else {
    mark.selectTrait(trait, label: label);
  }
  return true;
}
