import 'package:aves/features/batch_ops/view/batch_tool_catalog.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Explains what the batch engine can do and where it writes.
///
/// v1 has no saved profiles yet: the run sheet configures one run. This page is
/// the stable home for the tool catalog and the output folder, and the place the
/// copy-share settings will join.
class BatchSettingsPage extends StatelessWidget {
  static const routeName = '/settings/batch';

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.settingsBatchPageTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.settingsBatchExplanation),
            ),
            ListTile(
              leading: const Icon(AIcons.folder),
              title: Text(l10n.settingsBatchOutputFolder),
              subtitle: Text(l10n.settingsBatchOutputFolderValue),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.settingsBatchSupportedTools, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final info in batchToolCatalog)
              ListTile(
                leading: Icon(info.icon),
                title: Text(info.title(context)),
                subtitle: Text(info.description(context)),
              ),
          ],
        ),
      ),
    );
  }
}
