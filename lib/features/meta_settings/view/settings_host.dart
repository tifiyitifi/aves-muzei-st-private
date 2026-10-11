import 'package:aves/features/meta_settings/settings_engine_controller.dart';
import 'package:aves/features/meta_settings/view/meta_settings_page.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/settings/settings_mobile_page.dart';
import 'package:aves/widgets/settings/settings_tv_page.dart';
import 'package:flutter/widgets.dart';

/// Composition point for the settings route.
///
/// Renders the fork-owned metadata surface when the v2 engine is active, and the
/// upstream surface otherwise. Rebuilds when the engine changes, so switching is
/// immediate and in-place.
class SettingsHost extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsEngineController,
      builder: (context, child) {
        if (settingsEngineController.isMeta) {
          return const MetaSettingsPage();
        }
        return settings.useTvLayout ? const SettingsTvPage() : const SettingsMobilePage();
      },
    );
  }
}
