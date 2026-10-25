import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_reset_setting.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// What the user answered when asked to reset the photo source.
typedef WallpaperSourceResetAnswer = ({bool confirmed, bool dontAskAgain});

/// Asks before the source drops every filter.
///
/// Resetting is one tap away from a filter set the user may have spent a while
/// building, so the action confirms by default. The answer also carries "don't
/// ask again", which the caller persists; the question itself lives in the
/// wallpaper slice, while the flag is a normal setting the user can turn back on.
Future<bool> confirmWallpaperSourceReset(BuildContext context) async {
  if (!WallpaperSourceResetSetting.enabled) return true;
  final answer = await showAvesDialog<WallpaperSourceResetAnswer>(
    context: context,
    builder: (context) => const _WallpaperSourceResetDialog(),
  );
  if (answer == null) return false;
  // Only a reset records the opt-out: dismissing the question (or cancelling)
  // must not silently disable it, exactly like the catalogue prompt.
  if (answer.confirmed && answer.dontAskAgain) {
    WallpaperSourceResetSetting.setEnabled(false);
  }
  return answer.confirmed;
}

class _WallpaperSourceResetDialog extends StatefulWidget {
  const new();

  @override
  State<_WallpaperSourceResetDialog> createState() => _WallpaperSourceResetDialogState();
}

class _WallpaperSourceResetDialogState extends State<_WallpaperSourceResetDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesDialog(
      title: l10n.muzeiWallpaperSourceResetTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.muzeiWallpaperSourceResetMessage),
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
          onPressed: () => Navigator.maybeOf(context)?.pop<WallpaperSourceResetAnswer>((confirmed: false, dontAskAgain: false)),
          child: Text(Themes.asButtonLabel(MaterialLocalizations.of(context).cancelButtonLabel)),
        ),
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop<WallpaperSourceResetAnswer>((confirmed: true, dontAskAgain: _dontAskAgain)),
          child: Text(Themes.asButtonLabel(l10n.muzeiWallpaperSourcesUseAllPhotos)),
        ),
      ],
    );
  }
}
