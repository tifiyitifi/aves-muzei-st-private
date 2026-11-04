import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Why the fork edits a copy instead of the original.
///
/// Shown once before the first edit. The explanation is deliberately concrete: OEM editors differ
/// in whether they overwrite their input or write a new file, so the app copies first and only ever
/// hands the copy to an editor.
Future<void> showRefraEditIntroDialog(BuildContext context) async {
  final l10n = context.l10n;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.refraEditIntroTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: .start,
          children: [
            Text(l10n.refraEditIntroBody),
            const SizedBox(height: 12),
            Text(l10n.refraEditIntroSafety),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.refraEditIntroUnderstood),
        ),
      ],
    ),
  );
}

/// How the user wants to edit the staged copy.
enum RefraEditorChoice { builtIn, otherApp }

/// Asks which editor should open the staged copy; null when the sheet is dismissed.
Future<RefraEditorChoice?> showRefraEditorChooser(BuildContext context) {
  final l10n = context.l10n;
  return showModalBottomSheet<RefraEditorChoice>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.refraEditChooseEditorTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_fix_high),
            title: Text(l10n.refraEditChooseBuiltIn),
            subtitle: Text(l10n.refraEditChooseBuiltInSubtitle),
            onTap: () => Navigator.of(context).pop(RefraEditorChoice.builtIn),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(l10n.refraEditChooseOtherApp),
            subtitle: Text(l10n.refraEditChooseOtherAppSubtitle),
            onTap: () => Navigator.of(context).pop(RefraEditorChoice.otherApp),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
