import 'package:aves/features/media_ops/engine/media_op_prefs.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Undoes a remembered permission denial, in either settings surface.
///
/// Only shown while prompts are disabled: it exists to recover from a refusal
/// that was not meant as "never ask again", so leaving it visible otherwise
/// would offer a no-op.
class MediaOpPermissionResetTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(context.l10n.settingsMediaOpPermissionResetTile),
      onTap: () async {
        await mediaOpPrefs.resetPermissionPrompt();
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.settingsMediaOpPermissionResetDone)),
        );
      },
    );
  }
}
