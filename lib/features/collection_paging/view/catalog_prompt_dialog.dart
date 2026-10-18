import 'package:aves/features/collection_paging/catalog/catalog_prompt.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Asks whether to catalogue a large backlog in the background.
///
/// A null answer means the dialog was dismissed, which counts as "not now": the
/// question is asked at most once per session, so a dismissal cannot loop.
Future<CatalogPromptAnswer?> showCatalogPromptDialog(BuildContext context, {required int count}) => showAvesDialog<CatalogPromptAnswer>(
  context: context,
  builder: (context) => CatalogPromptDialog(count: count),
);

class CatalogPromptDialog extends StatefulWidget {
  /// The uncatalogued row count, shown so the user can judge the wait.
  final int count;

  const new({super.key, required this.count});

  @override
  State<CatalogPromptDialog> createState() => _CatalogPromptDialogState();
}

class _CatalogPromptDialogState extends State<CatalogPromptDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesDialog(
      title: l10n.catalogPromptDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.catalogPromptDialogMessage(widget.count)),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _dontAskAgain,
            onChanged: (value) => setState(() {
              _dontAskAgain = value ?? false;
            }),
            title: Text(l10n.catalogPromptDontAskAgain),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop(CatalogPromptAnswer.notNow),
          child: Text(Themes.asButtonLabel(l10n.catalogPromptLaterButton)),
        ),
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop(_dontAskAgain ? CatalogPromptAnswer.alwaysCatalogue : CatalogPromptAnswer.catalogueNow),
          child: Text(Themes.asButtonLabel(l10n.catalogPromptCatalogueButton)),
        ),
      ],
    );
  }
}
