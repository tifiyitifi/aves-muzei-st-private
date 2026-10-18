import 'dart:async';

import 'package:aves/features/collection_paging/lens/paged_collection_lens.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/grid/header.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the trailing widget an album section header shows for [directory].
///
/// Only a paged collection has pending catalog work to surface: the legacy path
/// loads every entry (and catalogues it) up front, so it gets no badge.
Widget? buildAlbumCatalogBadge(CollectionLens collection, String? directory) {
  if (directory == null) return null;
  final lens = collection;
  if (lens is! PagedCollectionLens || lens.source.summaries == null) return null;
  return AlbumCatalogBadge(lens: lens, directory: directory);
}

/// How many of one album's rows still need cataloguing, and a tap to start it.
///
/// A paged collection paints from the MediaStore mirror and fills the deep
/// metadata behind it, so an album can show long before it is catalogued. The
/// badge surfaces that pending work for a single album — the album-scoped
/// counterpart of the whole-library prompt — and starts it without waiting for
/// the backlog sweep to reach the album.
class AlbumCatalogBadge extends StatelessWidget {
  final PagedCollectionLens lens;
  final String directory;

  /// Width the badge occupies in the header's trailing slot.
  ///
  /// Fixed, so `SectionHeader.getPreferredHeight` can reserve exactly what the
  /// header will lay out; a long count is scaled down to fit instead of
  /// widening the slot.
  static const width = 28.0;

  const new({super.key, required this.lens, required this.directory});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lens,
      builder: (context, _) {
        final count = lens.albumUncatalogued(directory);
        // Nothing pending: the slot stays empty rather than showing a zero.
        if (count <= 0) return const SizedBox.shrink();
        return Tooltip(
          message: context.l10n.albumCatalogBadgeTooltip(count),
          child: InkWell(
            onTap: () => unawaited(lens.catalogAlbum(directory)),
            borderRadius: const BorderRadius.all(Radius.circular(9)),
            child: SizedBox(
              width: width,
              height: SectionHeader.leadingSize.height,
              child: Center(child: _pill(context, count)),
            ),
          ),
        );
      },
    );
  }

  Widget _pill(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(9)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          count > 999 ? context.l10n.albumCatalogBadgeOverflow : '$count',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
