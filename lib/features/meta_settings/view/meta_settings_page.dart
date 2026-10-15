import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/view/catalog_check.dart';
import 'package:aves/features/meta_settings/view/meta_settings_view.dart';
import 'package:aves/features/meta_settings/view/search/meta_settings_search_page_route.dart';
import 'package:aves/model/settings/enums/accessibility_animations.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/bars/app_bar_title.dart';
import 'package:aves/widgets/common/basic/font_size_icon_theme.dart';
import 'package:aves/widgets/common/basic/insets.dart';
import 'package:aves/widgets/common/basic/popup/menu_row.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/settings_action_delegate.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// The fork-owned metadata settings surface (v2).
///
/// Shown instead of the upstream page while the v2 engine is active. It is built
/// from the declarative catalog; the engine selector is always present so the
/// user can return to v1, and export/import delegate to the shared action
/// delegate.
class MetaSettingsPage extends StatefulWidget {
  const new({super.key});

  @override
  State<MetaSettingsPage> createState() => _MetaSettingsPageState();
}

class _MetaSettingsPageState extends State<MetaSettingsPage> {
  @override
  void initState() {
    super.initState();
    // Structural catalog checks are a development guard; the release gate is a
    // coverage test asserting the catalog renders every category.
    assert(() {
      for (final problem in metaCatalogProblems()) {
        _log.w('meta settings catalog: $problem');
      }
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) {
    final animations = context.select<Settings, AccessibilityAnimations>((v) => v.accessibilityAnimations);
    return AvesScaffold(
      appBar: AppBar(
        title: InteractiveAppBarTitle(
          onTap: () => _goToSearch(context),
          child: Text(context.l10n.settingsPageTitle),
        ),
        actions: [
          IconButton(
            icon: const Icon(AIcons.search),
            onPressed: () => _goToSearch(context),
            tooltip: MaterialLocalizations.of(context).searchFieldLabel,
          ),
          PopupMenuButton<SettingsAction>(
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: SettingsAction.export,
                  child: MenuRow(text: context.l10n.settingsActionExport, icon: const Icon(AIcons.fileExport)),
                ),
                PopupMenuItem(
                  value: SettingsAction.import,
                  child: MenuRow(text: context.l10n.settingsActionImport, icon: const Icon(AIcons.fileImport)),
                ),
              ];
            },
            onSelected: (action) async {
              // wait for the popup menu to hide before proceeding with the action
              await Future.delayed(animations.popUpAnimationDelay * timeDilation);
              SettingsActionDelegate().onActionSelected(context, action);
            },
            popUpAnimationStyle: animations.popUpAnimationStyle,
          ),
        ].map((v) => FontSizeIconTheme(child: v)).toList(),
      ),
      body: const GestureAreaProtectorStack(
        child: SafeArea(
          bottom: false,
          child: AnimationLimiter(
            child: MetaSettingsView(),
          ),
        ),
      ),
    );
  }

  void _goToSearch(BuildContext context) {
    Navigator.maybeOf(context)?.push(
      MetaSettingsSearchPageRoute(context: context),
    );
  }
}
