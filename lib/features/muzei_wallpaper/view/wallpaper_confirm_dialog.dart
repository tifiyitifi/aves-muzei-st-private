import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// What the user answered to a wallpaper confirmation.
typedef WallpaperConfirmAnswer = ({bool confirmed, bool dontAskAgain});

/// Asks a wallpaper question that can be turned off with "don't ask again".
///
/// The caller supplies the wording and the setting the checkbox controls, so
/// resetting the source, deleting the copy and deleting from the wallpaper
/// viewer all keep the same interaction and only differ in text.
Future<bool> confirmWallpaperAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required bool Function() enabled,
  required void Function(bool) setEnabled,
}) async {
  if (!enabled()) return true;
  final answer = await showAvesDialog<WallpaperConfirmAnswer>(
    context: context,
    builder: (context) => _WallpaperConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    ),
  );
  if (answer == null) return false;
  // Only a confirmation records the opt-out: dismissing the question (or
  // cancelling) must not silently disable it.
  if (answer.confirmed && answer.dontAskAgain) {
    setEnabled(false);
  }
  return answer.confirmed;
}

class _WallpaperConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;

  const new({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  @override
  State<_WallpaperConfirmDialog> createState() => _WallpaperConfirmDialogState();
}

class _WallpaperConfirmDialogState extends State<_WallpaperConfirmDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesDialog(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _dontAskAgain,
            onChanged: (value) => setState(() {
              _dontAskAgain = value ?? false;
            }),
            title: Text(l10n.doNotAskAgain),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop<WallpaperConfirmAnswer>((confirmed: false, dontAskAgain: false)),
          child: Text(Themes.asButtonLabel(MaterialLocalizations.of(context).cancelButtonLabel)),
        ),
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop<WallpaperConfirmAnswer>((confirmed: true, dontAskAgain: _dontAskAgain)),
          child: Text(Themes.asButtonLabel(widget.confirmLabel)),
        ),
      ],
    );
  }
}
