import 'package:aves/features/collection_paging/view/collection_background_work_page.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// The one-time explanation of the paged engine's first run.
///
/// Shown once, when a collection first imports an unseen library: the grid is
/// browsable immediately, the rest is organized in the background, and the
/// reference times say what "a while" means at different library sizes. The
/// same text stays available in the settings afterwards.
Future<void> showCollectionImportIntroDialog(BuildContext context, {required int libraryCount}) => showAvesDialog<void>(
      context: context,
      builder: (context) => CollectionImportIntroDialog(libraryCount: libraryCount),
    );

class CollectionImportIntroDialog extends StatelessWidget {
  /// The library size, for the "compare with the table" line; 0 when unknown.
  final int libraryCount;

  const new({
    super.key,
    required this.libraryCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    void close() => navigator.pop();
    return AvesDialog(
      title: l10n.collectionImportIntroTitle,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.collectionImportIntroBody),
            const SizedBox(height: 16),
            const CollectionImportEtaTable(),
            if (libraryCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.collectionImportEtaYours(libraryCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Pushed from the popped route's navigator: the dialog's context is
            // gone by the time the settings page animates in.
            navigator.pop();
            navigator.push(
              MaterialPageRoute(
                settings: const RouteSettings(name: CollectionBackgroundWorkPage.routeName),
                builder: CollectionBackgroundWorkPage.routeBuilder,
              ),
            );
          },
          child: Text(Themes.asButtonLabel(l10n.collectionImportIntroDetails)),
        ),
        TextButton(
          onPressed: close,
          child: Text(Themes.asButtonLabel(l10n.collectionImportIntroAcknowledge)),
        ),
      ],
    );
  }
}

/// Reference times for a first import, by library size.
///
/// Static on purpose: a live estimate would only be as good as the guess it is
/// made from, while these numbers come from measured runs; the app's own
/// progress stays the authoritative figure.
class CollectionImportEtaTable extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final rows = [
      l10n.collectionImportEtaTier1,
      l10n.collectionImportEtaTier2,
      l10n.collectionImportEtaTier3,
      l10n.collectionImportEtaTier4,
      l10n.collectionImportEtaTier5,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.collectionImportEtaHeader, style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.bold)),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(row, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.collectionImportEtaFootnote,
          style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}
