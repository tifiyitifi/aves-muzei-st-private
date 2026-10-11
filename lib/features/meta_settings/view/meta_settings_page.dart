import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/settings_engine_controller.dart';
import 'package:aves/features/meta_settings/view/settings_engine_labels.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/common.dart';
import 'package:aves/widgets/dialogs/selection_dialogs/single_selection.dart';
import 'package:material_ui/material_ui.dart';

/// The fork-owned metadata settings surface (v2).
///
/// Shown instead of the upstream page while the v2 engine is active. It is built
/// from the fork's declarative catalog; settings are added incrementally, and
/// the engine selector is always present so the user can fall back to v1.
class MetaSettingsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return AvesScaffold(
      appBar: AppBar(
        title: Text(context.l10n.settingsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: const [
          _SettingsEngineTile(),
        ],
      ),
    );
  }
}

class _SettingsEngineTile extends StatelessWidget {
  const new();

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
