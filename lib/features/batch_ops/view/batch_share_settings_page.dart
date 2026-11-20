import 'dart:async';

import 'package:aves/features/batch_ops/db/batch_profile_store.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/services/batch_share_service.dart';
import 'package:aves/features/batch_ops/view/batch_share_intro_dialog.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/basic/divider.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Explains where copy & share writes, how long it keeps the copies, and which
/// share profiles exist.
///
/// Kept separate from the batch settings page: batch results need replace/move
/// decisions, share output has none. The page is reachable from the settings
/// catalog, the share explainer and the share sheet.
class BatchShareSettingsPage extends StatefulWidget {
  static const routeName = '/settings/batch/share';

  const new({super.key});

  @override
  State<BatchShareSettingsPage> createState() => _BatchShareSettingsPageState();
}

class _BatchShareSettingsPageState extends State<BatchShareSettingsPage> {
  List<BatchProfile>? _profiles;
  int _retention = BatchSettings.defaultShareRetentionDays;

  @override
  void initState() {
    super.initState();
    unawaited(_load(prune: true));
  }

  Future<void> _load({bool prune = false}) async {
    await batchSettings.ensureLoaded();
    // Opening the page is a natural moment to honour the retention setting.
    if (prune) await batchShareService.pruneExpired();
    final db = await getIt<AppDatabaseProvider>().open();
    final profileStore = BatchProfileStore(db);
    await profileStore.ensureSeeded(BatchProfileKind.share);
    final profiles = await profileStore.getProfiles(BatchProfileKind.share);
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _retention = batchSettings.shareRetentionDays;
    });
  }

  Future<void> _setRetention(int days) async {
    await batchSettings.setShareRetentionDays(days);
    if (mounted) setState(() => _retention = days);
    await batchShareService.pruneExpired();
  }

  Future<void> _activate(BatchProfile profile) async {
    final db = await getIt<AppDatabaseProvider>().open();
    await BatchProfileStore(db).setActive(BatchProfileKind.share, profile.id);
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

  void _openAlbum() {
    final source = context.read<CollectionSource>();
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: CollectionPage.routeName),
        builder: (_) => CollectionPage(
          source: source,
          filters: {StoredAlbumFilter(batchShareService.directory, null)},
        ),
      ),
    );
  }

  String _nameOf(BatchProfile profile) => profile.name.isEmpty ? context.l10n.batchProfileDefaultName : profile.name;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final profiles = _profiles;

    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.batchShareSettingsTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.batchShareSettingsExplanation),
            ),
            ListTile(
              leading: const Icon(AIcons.folder),
              title: Text(l10n.batchShareSettingsOutputFolder),
              subtitle: Text(batchShareService.directory),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.batchShareSettingsOpenAlbum),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAlbum,
            ),
            const ThinDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.batchShareSettingsRetentionSection, style: theme.textTheme.titleMedium),
            ),
            RadioGroup<int>(
              groupValue: _retention,
              onChanged: (value) {
                if (value != null) unawaited(_setRetention(value));
              },
              child: Column(
                children: [
                  for (final days in BatchSettings.shareRetentionOptions)
                    RadioListTile<int>(
                      value: days,
                      title: Text(days <= 0 ? l10n.batchShareRetentionOff : l10n.batchShareRetentionDays(days)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(l10n.batchShareSettingsRetentionHint, style: theme.textTheme.bodySmall),
            ),
            const ThinDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.batchShareSettingsProfilesSection, style: theme.textTheme.titleMedium),
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
              child: Text(l10n.batchShareSettingsProfilesHint, style: theme.textTheme.bodySmall),
            ),
            const ThinDivider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.batchShareSettingsIntro),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showBatchShareIntroDialog(context, confirmLabel: MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
