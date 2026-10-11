import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/settings_engine_controller.dart';
import 'package:aves/features/meta_settings/view/settings_engine_labels.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/common.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/single_selection.dart';
import 'package:material_ui/material_ui.dart';

/// Custom editor for the settings engine selector on the v2 surface.
class SettingsEngineEditor extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsEngineController,
      builder: (context, child) {
        final version = settingsEngineController.version;
        return ListTile(
          leading: const Icon(AIcons.settings),
          title: Text(context.l10n.settingsEngineTile),
          subtitle: Text(settingsEngineName(context, version)),
          onTap: () => showSelectionDialog<SettingsEngineVersion>(
            context: context,
            builder: (context) => AvesSingleSelectionDialog<SettingsEngineVersion>(
              initialValue: version,
              options: {
                for (final v in SettingsEngineVersion.values) v: settingsEngineName(context, v),
              },
              title: context.l10n.settingsEngineDialogTitle,
            ),
            onSelection: settingsEngineController.setVersion,
          ),
        );
      },
    );
  }
}
