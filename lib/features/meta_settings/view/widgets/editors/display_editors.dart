import 'package:aves/features/meta_settings/engine/meta_settings_engine.dart';
import 'package:aves/features/meta_settings/model/setting_def.dart';
import 'package:aves/features/meta_settings/view/widgets/editors/bin_usage.dart';
import 'package:aves/features/meta_settings/view/widgets/meta_switch_list_tile.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

/// `themeColorMode` is an enum but presents as a switch (highlights on/off).
class ThemeColorModeEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSwitchListTile(
        selector: (context, settings) => settings.themeColorMode == AvesThemeColorMode.polychrome,
        onChanged: (value) => metaSettingsEngine.apply(
          def,
          (value ? AvesThemeColorMode.polychrome : AvesThemeColorMode.monochrome).name,
        ),
        title: def.title,
      );
}

/// `forceTvLayout` needs a pre-write confirmation and must turn the bin off.
class ForceTvLayoutEditor extends StatelessWidget {
  final SettingDef def;

  const new({super.key, required this.def});

  @override
  Widget build(BuildContext context) => MetaSwitchListTile(
        selector: (context, settings) => settings.forceTvLayout,
        onChanged: (value) async {
          if (value) {
            final l10n = context.l10n;
            if (!await showConfirmationDialog(
              context: context,
              message: [
                l10n.settingsModificationWarningDialogMessage,
                l10n.genericDangerWarningDialogMessage,
              ].join('\n\n'),
              ok: l10n.applyButtonLabel,
            )) {
              return;
            }
          }

          if (value && !(await setBinUsage(context, false))) return;

          metaSettingsEngine.apply(def, value);
        },
        title: def.title,
      );
}
