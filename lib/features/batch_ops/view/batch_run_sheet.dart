import 'dart:async';

import 'package:aves/features/batch_ops/db/batch_profile_store.dart';
import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_job.dart';
import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/features/batch_ops/services/batch_run_controller.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/services/batch_share_service.dart';
import 'package:aves/features/batch_ops/view/batch_action_editor.dart';
import 'package:aves/features/batch_ops/view/batch_progress_dialog.dart';
import 'package:aves/features/batch_ops/view/batch_results_page.dart';
import 'package:aves/features/batch_ops/view/batch_tool_catalog.dart';
import 'package:aves/features/drift_db/app_database_provider.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/widgets/collection/collection_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Entry point for the collection/viewer batch and copy & share actions.
///
/// The sheet only selects and configures actions; the run itself lives in
/// [BatchRunController] so the same flow can be driven by a saved profile or by
/// copy & share without a second engine. [kind] decides only where the output
/// goes and which profiles are offered.
Future<void> startBatch(BuildContext context, Set<AvesEntry> entries, {BatchProfileKind kind = BatchProfileKind.batch}) async {
  final l10n = context.l10n;
  final share = kind == BatchProfileKind.share;
  final images = entries.where((entry) => entry.isImage && !entry.isRaw).toSet();
  if (images.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(share ? l10n.batchShareNoImageFeedback : l10n.batchNoImageFeedback)));
    return;
  }

  await batchSettings.ensureLoaded();
  final actions = await showBatchRunSheet(context, images.length, kind: kind);
  if (actions == null || actions.isEmpty || !context.mounted) return;

  final output = BatchOutput(
    relativePath: share ? batchShareRelativeRoot : batchResultsRelativeRoot,
    // Replace-previous keeps the plain source name; keeping versions needs a
    // distinct name per run so the older result is not overwritten in place.
    // A share run has no supersede pass, so it always dates the copy.
    namePattern: share || batchSettings.resultMode == BatchResultMode.keepVersions ? '{name}_{date}' : '{name}',
  );

  // Share output expires; the cleanup is bounded to the share folder and must
  // never delay or fail the run it precedes.
  if (share) await batchShareService.pruneExpired();

  final controller = BatchRunController();
  unawaited(controller.run(entries: images, actions: actions, output: output));
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BatchProgressDialog(controller: controller),
  );
  await controller.recordsSettled;
  final done = controller.done;
  controller.dispose();
  if (!share) unawaited(batchResultsService.pruneSupersededFiles());
  if (!context.mounted || done == 0) return;

  if (share) {
    final navigator = Navigator.maybeOf(context);
    final source = context.read<CollectionSource>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.batchShareReady(done)),
        action: SnackBarAction(
          label: l10n.batchViewResults,
          onPressed: () => navigator?.push(
            MaterialPageRoute(
              settings: const RouteSettings(name: CollectionPage.routeName),
              builder: (_) => CollectionPage(
                source: source,
                filters: {StoredAlbumFilter(batchShareService.directory, null)},
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l10n.batchResultsReady(done)),
      action: SnackBarAction(
        label: l10n.batchViewResults,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BatchResultsPage()),
        ),
      ),
    ),
  );
}

Future<List<BatchAction>?> showBatchRunSheet(BuildContext context, int entryCount, {BatchProfileKind kind = BatchProfileKind.batch}) {
  return showModalBottomSheet<List<BatchAction>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => BatchRunSheet(entryCount: entryCount, kind: kind),
  );
}

class BatchRunSheet extends StatefulWidget {
  final int entryCount;
  final BatchProfileKind kind;

  const new({super.key, required this.entryCount, this.kind = BatchProfileKind.batch});

  @override
  State<BatchRunSheet> createState() => _BatchRunSheetState();
}

class _BatchRunSheetState extends State<BatchRunSheet> {
  late final List<BatchAction> _actions = batchRunnableCatalog.map((info) => info.createDefault().copyWith(enabled: false)).toList();
  List<BatchProfile>? _profiles;
  String? _selectedProfileId;

  List<BatchAction> get _enabledActions => _actions.where((action) => action.enabled).toList();

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  Future<void> _loadProfiles() async {
    try {
      final store = BatchProfileStore(await getIt<AppDatabaseProvider>().open());
      await store.ensureSeeded(widget.kind);
      final profiles = await store.getProfiles(widget.kind);
      if (!mounted) return;
      setState(() => _profiles = profiles);
      // "Used by default" means exactly that: the sheet starts from the active
      // profile, and the user can still change every row before running.
      final active = profiles.where((profile) => profile.isActive).firstOrNull;
      if (active != null && _selectedProfileId == null) _applyProfile(active);
    } catch (_) {
      if (mounted) setState(() => _profiles = const []);
    }
  }

  Future<void> _edit(int index) async {
    final edited = await showBatchActionEditor(context, _actions[index]);
    if (edited == null || !mounted) return;
    setState(() => _actions[index] = edited.copyWith(enabled: true));
  }

  /// Applies a saved chain to the sheet's fixed catalog.
  ///
  /// The sheet owns one row per runnable tool, so a profile only decides which
  /// rows are enabled and with which settings; a profile action this build no
  /// longer offers is ignored instead of inventing a row for it.
  void _applyProfile(BatchProfile profile) {
    final saved = {for (final action in profile.actions) action.kind: action};
    setState(() {
      _selectedProfileId = profile.id;
      for (var index = 0; index < _actions.length; index++) {
        final action = saved[_actions[index].kind];
        if (action == null) continue;
        _actions[index] = action;
      }
    });
  }

  Future<void> _saveProfile() async {
    final l10n = context.l10n;
    final name = await showDialog<String>(
      context: context,
      // Always a new profile: re-using the current name would silently create a
      // duplicate, and editing an existing profile is a separate action.
      builder: (context) => const _ProfileNameDialog(initialName: ''),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final store = BatchProfileStore(await getIt<AppDatabaseProvider>().open());
    final now = DateTime.now();
    final profile = BatchProfile(
      id: '${widget.kind.name}-${now.microsecondsSinceEpoch}',
      name: name,
      actionsJson: encodeBatchActions(_actions),
      kind: widget.kind,
      sortOrder: (_profiles?.length ?? 0) + 1,
      isActive: false,
      createdAt: now,
      updatedAt: now,
    );
    await store.saveProfile(profile);
    await _loadProfiles();
    if (!mounted) return;
    setState(() => _selectedProfileId = profile.id);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.batchProfileSaved(name))));
  }

  String _profileName(BatchProfile? profile) {
    if (profile == null) return '';
    return profile.name.isEmpty ? context.l10n.batchProfileDefaultName : profile.name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final share = widget.kind == BatchProfileKind.share;
    final profiles = _profiles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(share ? l10n.batchShareRunSheetTitle : l10n.batchRunSheetTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(share ? l10n.batchShareRunSheetExplanation : l10n.batchRunSheetExplanation),
              const SizedBox(height: 4),
              Text(
                share ? l10n.batchShareRunSheetOutputFolder(batchShareService.directory) : l10n.batchRunSheetOutputFolder(batchResultsService.resultsDirectory),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (profiles != null && profiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: profiles.any((profile) => profile.id == _selectedProfileId) ? _selectedProfileId : null,
                    hint: Text(l10n.batchProfilePickerHint),
                    items: [
                      for (final profile in profiles)
                        DropdownMenuItem(value: profile.id, child: Text(_profileName(profile), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (id) {
                      final profile = profiles.firstWhereOrNull((profile) => profile.id == id);
                      if (profile != null) _applyProfile(profile);
                    },
                  ),
                ),
                TextButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(l10n.batchProfileSave),
                ),
              ],
            ),
          ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _actions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final action = _actions[index];
              final info = batchToolInfo(action.kind);
              return ListTile(
                leading: Icon(info.icon),
                title: Text(info.title(context)),
                subtitle: Text(info.description(context)),
                trailing: Switch(
                  value: action.enabled,
                  onChanged: (value) => setState(() => _actions[index] = action.copyWith(enabled: value)),
                ),
                onTap: () => _edit(index),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.batchRunSelectedCount(widget.entryCount)),
                    if (_enabledActions.isEmpty)
                      Text(l10n.batchRunNothingSelected, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _enabledActions.isEmpty ? null : () => Navigator.pop(context, _enabledActions),
                child: Text(l10n.batchRunButton),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileNameDialog extends StatefulWidget {
  final String initialName;

  const new({required this.initialName});

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.batchProfileSave),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.batchProfileNameLabel),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: Text(l10n.saveTooltip)),
      ],
    );
  }
}
