import 'package:aves/features/media_ops/engine/media_op_keys.dart';
import 'package:aves/features/media_ops/engine/media_op_prefs.dart';
import 'package:aves/features/media_ops/model/media_op_engine.dart';
import 'package:aves/features/media_ops/view/media_op_labels.dart';
import 'package:aves/features/media_ops/view/media_op_permission_reset_tile.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/common/tiles/single_selection.dart';
import 'package:aves/widgets/settings/settings_definition.dart';
import 'package:material_ui/material_ui.dart';

/// The media operation engine selector, mounted in the upstream (v1) settings
/// surface so the switch stays reachable while the v2 surface is disabled.
class MediaOpEngineTile extends SettingsTile {
  new();

  @override
  List<String> get settingKeys => [MediaOpKeys.engine];

  @override
  String title(BuildContext context) => context.l10n.settingsMediaOpEngineTile;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: mediaOpPrefs,
        builder: (context, child) => Column(
          children: [
            SettingsSelectionListTile<MediaOpEngine>(
              values: MediaOpEngine.values,
              getName: mediaOpEngineName,
              selector: (context, s) => mediaOpPrefs.engine,
              onSelection: mediaOpPrefs.setEngine,
              tileTitle: title,
              dialogTitle: context.l10n.settingsMediaOpEngineDialogTitle,
              optionSubtitleBuilder: (v) => v == mediaOpPrefs.engine ? null : mediaOpEngineDescription(context, v),
            ),
            if (!mediaOpPrefs.allowPermissionPrompt) const MediaOpPermissionResetTile(),
          ],
        ),
      );
}
