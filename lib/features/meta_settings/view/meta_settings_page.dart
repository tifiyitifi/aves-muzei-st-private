import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/features/meta_settings/view/catalog_check.dart';
import 'package:aves/features/meta_settings/view/meta_settings_view.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

const _log = AreaKeyLog(LogKeys.settings);

/// The fork-owned metadata settings surface (v2).
///
/// Shown instead of the upstream page while the v2 engine is active. It is built
/// from the declarative catalog; categories not yet migrated fall back to a
/// fork-owned copy of the legacy section, and the engine selector is always
/// present so the user can return to v1.
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
    return AvesScaffold(
      appBar: AppBar(
        title: Text(context.l10n.settingsPageTitle),
      ),
      body: const SafeArea(
        bottom: false,
        child: MetaSettingsView(),
      ),
    );
  }
}
