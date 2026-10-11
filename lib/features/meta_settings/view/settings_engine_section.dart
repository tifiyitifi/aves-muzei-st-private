import 'package:aves/features/meta_settings/model/enum/settings_engine_version.dart';
import 'package:aves/features/meta_settings/settings_engine_controller.dart';
import 'package:aves/features/meta_settings/store/settings_engine_gate.dart';
import 'package:aves/features/meta_settings/view/settings_engine_labels.dart';
import 'package:aves/theme/colors.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/common/tile_leading.dart';
import 'package:aves/widgets/settings/common/tiles/single_selection.dart';
import 'package:aves/widgets/settings/settings_definition.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The engine selector, mounted in the upstream settings surface.
///
/// This adapter is the one allowed reference to the upstream `SettingsSection`
/// abstraction; the v2 surface itself is fork-owned.
class SettingsVersionSection extends SettingsSection {
  @override
  String get key => 'settings-engine';

  @override
  Widget icon(BuildContext context) => SettingsTileLeading(
        icon: AIcons.settings,
        color: context.select<AvesColorsData, Color>((v) => v.fromHue(200)),
      );

  @override
  String title(BuildContext context) => context.l10n.settingsAdvancedSectionTitle;

  @override
  Future<List<SettingsTile>> tiles(BuildContext context) => Future.value([SettingsVersionTile()]);
}

class SettingsVersionTile extends SettingsTile {
  new();

  @override
  List<String> get settingKeys => [SettingsEngineGate.key];

  @override
  String title(BuildContext context) => context.l10n.settingsEngineTile;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: settingsEngineController,
        builder: (context, child) => SettingsSelectionListTile<SettingsEngineVersion>(
          values: SettingsEngineVersion.values,
          getName: settingsEngineName,
          selector: (context, s) => settingsEngineController.version,
          onSelection: settingsEngineController.setVersion,
          tileTitle: title,
          dialogTitle: context.l10n.settingsEngineDialogTitle,
          optionSubtitleBuilder: (v) => v == settingsEngineController.version ? null : context.l10n.settingsEngineDescription,
        ),
      );
}
