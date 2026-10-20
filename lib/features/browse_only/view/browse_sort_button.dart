import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Sort menu for the browse-only media grids.
///
/// The choices are the sort and its direction in one entry: the browser has no
/// room for a second menu, and "date, oldest first" is the thing a user picks,
/// not two independent switches.
class BrowseMediaSortButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: browsePrefs,
      builder: (context, child) {
        final l10n = context.l10n;
        final currentSort = browsePrefs.mediaSort;
        final currentReverse = browsePrefs.mediaReverse;
        final choices = <_MediaChoice>[
          const _MediaChoice(BrowseMediaSort.date, false, factor: _SortFactor.date, order: _SortOrder.newestFirst),
          const _MediaChoice(BrowseMediaSort.date, true, factor: _SortFactor.date, order: _SortOrder.oldestFirst),
          const _MediaChoice(BrowseMediaSort.name, false, factor: _SortFactor.name, order: _SortOrder.atoZ),
          const _MediaChoice(BrowseMediaSort.name, true, factor: _SortFactor.name, order: _SortOrder.ztoA),
        ];
        return PopupMenuButton<_MediaChoice>(
          icon: const Icon(Icons.sort),
          itemBuilder: (context) => [
            for (final choice in choices)
              CheckedPopupMenuItem<_MediaChoice>(
                value: choice,
                checked: choice.sort == currentSort && choice.reverse == currentReverse,
                height: 56,
                child: _SortLabel(
                  factor: switch (choice.factor) {
                    _SortFactor.date => l10n.sortByDate,
                    _SortFactor.name => l10n.sortByName,
                    _ => l10n.sortByItemCount,
                  },
                  order: switch (choice.order) {
                    _SortOrder.newestFirst => l10n.sortOrderNewestFirst,
                    _SortOrder.oldestFirst => l10n.sortOrderOldestFirst,
                    _SortOrder.atoZ => l10n.sortOrderAtoZ,
                    _SortOrder.ztoA => l10n.sortOrderZtoA,
                    _ => l10n.sortOrderHighestFirst,
                  },
                ),
              ),
          ],
          onSelected: (choice) => browsePrefs.setMediaSort(choice.sort, choice.reverse),
        );
      },
    );
  }
}

/// Sort menu for the browse-only album grid.
class BrowseAlbumSortButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: browsePrefs,
      builder: (context, child) {
        final l10n = context.l10n;
        final currentSort = browsePrefs.albumSort;
        final currentReverse = browsePrefs.albumReverse;
        final choices = <_AlbumChoice>[
          const _AlbumChoice(BrowseAlbumSort.date, false, factor: _SortFactor.date, order: _SortOrder.newestFirst),
          const _AlbumChoice(BrowseAlbumSort.date, true, factor: _SortFactor.date, order: _SortOrder.oldestFirst),
          const _AlbumChoice(BrowseAlbumSort.name, false, factor: _SortFactor.name, order: _SortOrder.atoZ),
          const _AlbumChoice(BrowseAlbumSort.name, true, factor: _SortFactor.name, order: _SortOrder.ztoA),
          const _AlbumChoice(BrowseAlbumSort.count, false, factor: _SortFactor.count, order: _SortOrder.highestFirst),
          const _AlbumChoice(BrowseAlbumSort.count, true, factor: _SortFactor.count, order: _SortOrder.lowestFirst),
        ];
        return PopupMenuButton<_AlbumChoice>(
          icon: const Icon(Icons.sort),
          itemBuilder: (context) => [
            for (final choice in choices)
              CheckedPopupMenuItem<_AlbumChoice>(
                value: choice,
                checked: choice.sort == currentSort && choice.reverse == currentReverse,
                height: 56,
                child: _SortLabel(
                  factor: switch (choice.factor) {
                    _SortFactor.date => l10n.sortByDate,
                    _SortFactor.name => l10n.sortByName,
                    _SortFactor.count => l10n.sortByItemCount,
                  },
                  order: switch (choice.order) {
                    _SortOrder.newestFirst => l10n.sortOrderNewestFirst,
                    _SortOrder.oldestFirst => l10n.sortOrderOldestFirst,
                    _SortOrder.atoZ => l10n.sortOrderAtoZ,
                    _SortOrder.ztoA => l10n.sortOrderZtoA,
                    _SortOrder.highestFirst => l10n.sortOrderHighestFirst,
                    _SortOrder.lowestFirst => l10n.sortOrderLowestFirst,
                  },
                ),
              ),
          ],
          onSelected: (choice) => browsePrefs.setAlbumSort(choice.sort, choice.reverse),
        );
      },
    );
  }
}

enum _SortFactor { date, name, count }

enum _SortOrder { newestFirst, oldestFirst, atoZ, ztoA, highestFirst, lowestFirst }

class _MediaChoice {
  final BrowseMediaSort sort;
  final bool reverse;
  final _SortFactor factor;
  final _SortOrder order;

  const new(this.sort, this.reverse, {required this.factor, required this.order});
}

class _AlbumChoice {
  final BrowseAlbumSort sort;
  final bool reverse;
  final _SortFactor factor;
  final _SortOrder order;

  const new(this.sort, this.reverse, {required this.factor, required this.order});
}

class _SortLabel extends StatelessWidget {
  final String factor;
  final String order;

  const new({
    required this.factor,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(factor),
        Text(order, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
