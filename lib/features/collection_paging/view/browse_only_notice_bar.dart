import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/collection_background_work_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// The reduced mode a collection runs in while its first import fills the
/// database.
///
/// Browsing, sorting on what MediaStore already knows and file-name search work
/// from the first painted window. Everything that writes is paused: the import
/// and the catalogue that follows read each file's metadata, and an edit made
/// before they reach a row would be overwritten by what they read. Aggregates
/// are paused for a different reason — summing half a library gives a number
/// nobody should trust.
///
/// The mode ends by itself when the import finishes; the app bar's notice strip
/// disappears with it, so the unlock is visible without a restart.
abstract final class BrowseOnlyMode {
  /// Whether the reduced mode is running.
  static bool get isActive => pagedImportStatus.active;

  /// Collection actions that are greyed out while it runs.
  static const Set<EntrySetAction> lockedActions = {
    // selection leads to the locked actions below
    .select,
    .selectAll,
    .selectByTrait,
    // one OS payload, and a set that is not the whole view yet
    .share,
    .copyToClipboard,
    // writes
    .delete,
    .copy,
    .move,
    .rename,
    .convert,
    .exportGpx,
    .toggleFavourite,
    .rotateCCW,
    .rotateCW,
    .flip,
    .editDate,
    .editLocation,
    .editTitleDescription,
    .editRating,
    .editTags,
    .removeMetadata,
    .restore,
    .emptyBin,
    .rescan,
    // aggregates over catalogued data
    .stats,
    .map,
  };

  static bool locks(EntrySetAction action) => isActive && lockedActions.contains(action);
}

/// The permanent strip under the collection app bar while the reduced mode runs.
///
/// It is the mode's own explanation surface: a mode that takes features away has
/// to say so where those features are, not only in a settings page the user has
/// no reason to open.
class BrowseOnlyNoticeBar extends StatelessWidget {
  /// Kept in sync with the bar's layout and added to the app bar's content
  /// height while the bar is shown.
  static const double preferredHeight = 40;

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: SizedBox(
        height: preferredHeight,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.sync, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.browseOnlyBarMessage,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                // The strip is 40 high: a default-sized button would overflow it.
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: color,
              ),
              onPressed: () => Navigator.maybeOf(context)?.push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: CollectionBackgroundWorkPage.routeName),
                  builder: CollectionBackgroundWorkPage.routeBuilder,
                ),
              ),
              child: Text(l10n.browseOnlyBarDetails),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
