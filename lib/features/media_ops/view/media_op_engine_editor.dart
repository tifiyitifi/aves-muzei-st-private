import 'package:aves/features/media_ops/engine/media_op_prefs.dart';
import 'package:aves/features/media_ops/model/media_op_engine.dart';
import 'package:aves/features/media_ops/view/media_op_labels.dart';
import 'package:aves/features/media_ops/view/media_op_permission_reset_tile.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/common.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/single_selection.dart';
import 'package:material_ui/material_ui.dart';

/// Custom editor for the media operation engine (legacy vs fast pipeline) on
/// the v2 settings surface.
///
/// Reads and writes [mediaOpPrefs] directly, bypassing the settings engine and
/// its guard: these keys are engine-independent by design.
class MediaOpEngineEditor extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mediaOpPrefs,
      builder: (context, child) {
        final engine = mediaOpPrefs.engine;
        return Column(
          children: [
            ListTile(
              leading: const Icon(AIcons.move),
              title: Text(context.l10n.settingsMediaOpEngineTile),
              subtitle: Text(mediaOpEngineName(context, engine)),
              onTap: () => showSelectionDialog<MediaOpEngine>(
                context: context,
                builder: (context) => AvesSingleSelectionDialog<MediaOpEngine>(
                  initialValue: engine,
                  options: {
                    for (final v in MediaOpEngine.values) v: mediaOpEngineName(context, v),
                  },
                  title: context.l10n.settingsMediaOpEngineDialogTitle,
                  optionSubtitleBuilder: (v) => v == engine ? null : mediaOpEngineDescription(context, v),
                ),
                onSelection: mediaOpPrefs.setEngine,
              ),
            ),
            if (!mediaOpPrefs.allowPermissionPrompt) const MediaOpPermissionResetTile(),
          ],
        );
      },
    );
  }
}
