import 'package:aves/features/collection_paging/catalog/catalog_progress.dart';
import 'package:aves/features/collection_paging/lens/paged_import_status.dart';
import 'package:aves/features/collection_paging/view/collection_count_line.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/events.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/view/view.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/extensions/theme.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

class SourceStateAwareAppBarTitle extends StatelessWidget {
  final Widget title;
  final CollectionSource source;

  /// The lens this bar describes, when there is one: it supplies the row counts
  /// shown once the collection is ready. Null on the album/explorer bars, which
  /// only report the source state.
  final CollectionLens? collection;

  const new({
    super.key,
    required this.title,
    required this.source,
    this.collection,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        title,
        ValueListenableBuilder<SourceState>(
          valueListenable: source.stateNotifier,
          builder: (context, sourceState, child) {
            return AnimatedSwitcher(
              duration: ADurations.appBarTitleAnimation,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  child: child,
                ),
              ),
              child: sourceState == SourceState.ready
                  ? (collection == null ? const SizedBox() : CollectionCountLine(collection: collection!))
                  : SourceStateSubtitle(
                      source: source,
                    ),
            );
          },
        ),
      ],
    );
  }
}

class SourceStateSubtitle extends StatelessWidget {
  final CollectionSource source;

  const new({
    super.key,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final sourceState = source.state;
    return AnimatedBuilder(
      animation: pagedImportStatus,
      builder: (context, child) {
        // While the first import runs, the state is `loading` in the engine's
        // terms but "organizing" to the user, which is also what the settings
        // page and the one-time explainer call it.
        final subtitle = pagedImportStatus.active ? context.l10n.sourceStateImporting : sourceState.getName(context.l10n);
        if (subtitle == null) return const SizedBox();

        final theme = Theme.of(context);
        return DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.disable('smcp')]),
          child: ValueListenableBuilder<ProgressEvent>(
            valueListenable: source.progressNotifier,
            builder: (context, progress, snapshot) {
              return ValueListenableBuilder<CatalogProgress?>(
                valueListenable: catalogProgressNotifier,
                builder: (context, catalogProgress, snapshot) {
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: subtitle),
                        if (progress.total != 0 && progress.done > 0 && sourceState != SourceState.locatingCountries) ...[
                          const WidgetSpan(child: SizedBox(width: 8)),
                          TextSpan(
                            text: '${progress.done}/${progress.total}',
                            style: TextStyle(color: theme.isDark ? Colors.white30 : Colors.black26),
                          ),
                        ],
                        // The pass's own clock: how long it has run, and how long it
                        // is likely to take.
                        if (catalogProgress != null && catalogProgress.done > 0) ...[
                          const WidgetSpan(child: SizedBox(width: 8)),
                          TextSpan(
                            text: _catalogProgressLabel(context, catalogProgress),
                            style: TextStyle(color: theme.isDark ? Colors.white30 : Colors.black26),
                          ),
                        ],
                      ],
                    ),
                    softWrap: false,
                    overflow: .fade,
                    maxLines: 1,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  /// The pass's clock: elapsed, plus the estimate when one is trustworthy.
  String _catalogProgressLabel(BuildContext context, CatalogProgress progress) {
    final l10n = context.l10n;
    final elapsed = formatCatalogDuration(progress.elapsed);
    final remaining = progress.remaining;
    return remaining == null ? l10n.catalogProgressWithoutEta(elapsed) : l10n.catalogProgressWithEta(elapsed, formatCatalogDuration(remaining));
  }
}
