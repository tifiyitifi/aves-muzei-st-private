import 'dart:async';

import 'package:aves/features/batch_ops/db/batch_profile_store.dart';
import 'package:aves/features/batch_ops/db/batch_result_store.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/view/batch_results_page.dart';
import 'package:aves/features/batch_ops/view/batch_tool_catalog.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/divider.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Explains what the batch engine can do, where it writes, and what happens to
/// the results.
///
/// It is also the home of the two settings the results depend on (what a second
/// run does with the first result, and which profile is active) and the entry to
/// the results page.
class BatchSettingsPage extends StatefulWidget {
  static const routeName = '/settings/batch';

  const new({super.key});

  @override
  State<BatchSettingsPage> createState() => _BatchSettingsPageState();
}

class _BatchSettingsPageState extends State<BatchSettingsPage> {
  List<BatchProfile>? _profiles;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await batchSettings.ensureLoaded();
    // A result deleted from the album must not be counted or offered anymore.
    await batchResultsService.pruneMissingResults();
    final db = await getIt<AppDatabaseProvider>().open();
    final profileStore = BatchProfileStore(db);
    await profileStore.ensureSeeded(BatchProfileKind.batch);
    final profiles = await profileStore.getProfiles(BatchProfileKind.batch);
    final pending = await BatchResultStore(db).getPending();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _pendingCount = pending.length;
    });
  }

  Future<void> _setMode(BatchResultMode mode) async {
    await batchSettings.setResultMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _activate(BatchProfile profile) async {
    final db = await getIt<AppDatabaseProvider>().open();
    await BatchProfileStore(db).setActive(BatchProfileKind.batch, profile.id);
    await _load();
  }

  Future<void> _delete(BatchProfile profile) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.batchProfileDeleteTitle),
        content: Text(l10n.batchProfileDeleteBody(_nameOf(profile))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancelTooltip)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.deleteButtonLabel)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await getIt<AppDatabaseProvider>().open();
    await BatchProfileStore(db).deleteProfile(profile.id);
    await _load();
  }

  String _nameOf(BatchProfile profile) => profile.name.isEmpty ? context.l10n.batchProfileDefaultName : profile.name;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final profiles = _profiles;
    final mode = batchSettings.resultMode;

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
              subtitle: Text(batchResultsService.resultsDirectory),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.batchResultsPageTitle),
              subtitle: Text(l10n.batchResultsWaitingCount(_pendingCount)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BatchResultsPage()));
                await _load();
              },
            ),
            const ThinDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.batchSettingsResultsSection, style: theme.textTheme.titleMedium),
            ),
            RadioGroup<BatchResultMode>(
              groupValue: mode,
              onChanged: (value) {
                if (value != null) unawaited(_setMode(value));
              },
              child: Column(
                children: [
                  RadioListTile<BatchResultMode>(
                    value: BatchResultMode.replacePrevious,
                    title: Text(l10n.batchSettingsResultsModeReplace),
                    subtitle: Text(l10n.batchSettingsResultsModeReplaceDescription),
                  ),
                  RadioListTile<BatchResultMode>(
                    value: BatchResultMode.keepVersions,
                    title: Text(l10n.batchSettingsResultsModeKeep),
                    subtitle: Text(l10n.batchSettingsResultsModeKeepDescription),
                  ),
                ],
              ),
            ),
            const ThinDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.batchSettingsProfilesSection, style: theme.textTheme.titleMedium),
            ),
            if (profiles == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              for (final profile in profiles)
                ListTile(
                  leading: Icon(profile.isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  title: Text(_nameOf(profile)),
                  subtitle: Text(profile.isActive ? l10n.batchSettingsProfileActive : l10n.batchSettingsProfileInactive),
                  onTap: () => unawaited(_activate(profile)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.deleteButtonLabel,
                    onPressed: () => unawaited(_delete(profile)),
                  ),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(l10n.batchSettingsProfilesHint, style: theme.textTheme.bodySmall),
            ),
            const ThinDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.settingsBatchSupportedTools, style: theme.textTheme.titleMedium),
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
