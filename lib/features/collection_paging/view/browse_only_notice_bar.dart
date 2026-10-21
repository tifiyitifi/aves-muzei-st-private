import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/collection_paging/engine/library_phase.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/collection_background_work_page.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// The app bar strip while the reduced mode runs, or null once it is over.
///
/// A browse page pushed before the handoff outlives it (the collection swaps
/// under it, it is not popped), so the strip belongs to the phase instead of
/// being written into that page's app bar once. Callers that do not rebuild on
/// the phase must listen to it to get the strip removed.
PreferredSizeWidget? browseOnlyNoticeBar() {
  if (!libraryPhase.isBrowsing && !pagedImportStatus.active) return null;
  return PreferredSize(
    preferredSize: const Size.fromHeight(BrowseOnlyNoticeBar.preferredHeight),
    child: BrowseOnlyNoticeBar(showNotice: collectionPagingPrefs.browseOnlyBar),
  );
}

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
  static bool get isActive => libraryPhase.isBrowsing || pagedImportStatus.active;

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
/// no reason to open. It carries the import counter too, on its own line: one
/// line could not show both what the app is doing and how far it has got
/// without cutting one of them.
class BrowseOnlyNoticeBar extends StatelessWidget {
  /// Kept in sync with the bar's layout and added to the app bar's content
  /// height while the bar is shown.
  static const double preferredHeight = 56;

  /// Whether to show the mode notice line. The import counter is always shown
  /// while a run is active: it is status, not the notice the setting hides.
  final bool showNotice;

  const new({super.key, this.showNotice = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    final l10n = context.l10n;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: SizedBox(
        height: preferredHeight,
        child: ListenableBuilder(
          listenable: Listenable.merge([pagedImportStatus, libraryPhase]),
          builder: (context, child) {
            final status = pagedImportStatus;
            final failed = libraryPhase.hasFailed;
            final formatter = settings.avesLocale.decimalNumberFormat();
            final statusLine = failed
                ? l10n.browseOnlyImportFailed
                : !status.active
                ? null
                : status.total > 0
                ? l10n.browseOnlyProgress(formatter.format(status.done), formatter.format(status.total))
                : l10n.sourceStateImporting;
            return Row(
              children: [
                const SizedBox(width: 16),
                Icon(failed ? Icons.error_outline : Icons.sync, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (statusLine != null)
                        Text(
                          statusLine,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: theme.textTheme.bodyMedium?.copyWith(color: color),
                        ),
                      if (showNotice)
                        Text(
                          l10n.browseOnlyBarMessage,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: theme.textTheme.bodySmall?.copyWith(color: color),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    // The strip is 56 high: a default-sized button would overflow.
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    foregroundColor: color,
                  ),
                  onPressed: failed
                      ? libraryPhase.retry
                      : () => Navigator.maybeOf(context)?.push(
                          MaterialPageRoute(
                            settings: const RouteSettings(name: CollectionBackgroundWorkPage.routeName),
                            builder: CollectionBackgroundWorkPage.routeBuilder,
                          ),
                        ),
                  child: Text(failed ? l10n.browseOnlyImportRetry : l10n.browseOnlyBarDetails),
                ),
                const SizedBox(width: 4),
              ],
            );
          },
        ),
      ),
    );
  }
}
