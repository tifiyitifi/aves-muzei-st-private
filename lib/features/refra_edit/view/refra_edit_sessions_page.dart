import 'dart:async';

import 'package:aves/features/refra_edit/model/refra_edit_session.dart';
import 'package:aves/features/refra_edit/services/refra_edit_service.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/enums.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/viewer/entry_viewer_page.dart';
import 'package:material_ui/material_ui.dart';

/// The copy-first edit sessions and the files each one produced.
///
/// A session can only be moved back to the directory its source came from; the page never offers
/// to apply a copy to the original file itself, because the original was never opened for writing.
class RefraEditSessionsPage extends StatefulWidget {
  static const routeName = '/settings/refra_edit/sessions';

  const new({super.key});

  @override
  State<RefraEditSessionsPage> createState() => _RefraEditSessionsPageState();
}

class _RefraEditSessionsPageState extends State<RefraEditSessionsPage> {

  List<RefraEditSession>? _sessions;
  StreamSubscription<List<RefraEditSession>>? _sub;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final store = await refraEditService.store();
    if (!mounted) return;
    await _sub?.cancel();
    _sub = store.watchSessions().listen((sessions) {
      if (mounted) setState(() => _sessions = sessions);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sessions = _sessions;
    return AvesScaffold(
      appBar: AppBar(title: Text(l10n.refraEditSessionsTitle)),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.refraEditNoSessions, textAlign: .center),
              ),
            )
          : ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) => _SessionTile(
                session: sessions[index],
                onChanged: () => setState(() {}),
              ),
            ),
    );
  }
}

class _SessionTile extends StatefulWidget {
  final RefraEditSession session;
  final VoidCallback onChanged;

  const new({
    required this.session,
    required this.onChanged,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  List<RefraEditOutput>? _outputs;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOutputs());
  }

  Future<void> _loadOutputs() async {
    final outputs = await refraEditService.refreshOutputs(widget.session);
    if (mounted) setState(() => _outputs = outputs);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final session = widget.session;
    final outputs = _outputs;
    final active = session.status == RefraEditSessionStatus.active;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(session.sourceName, style: theme.textTheme.titleMedium, maxLines: 2, overflow: .ellipsis),
            const SizedBox(height: 4),
            Text(
              l10n.refraEditSessionSource(session.sourceDirectory.isEmpty ? session.sourceUri : session.sourceDirectory),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: .ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.refraEditSessionResults(outputs?.length ?? 0),
              style: theme.textTheme.bodySmall,
            ),
            if (outputs != null && outputs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final output in outputs)
                      ActionChip(
                        avatar: const Icon(Icons.image_outlined, size: 18),
                        label: Text(
                          output.fileName,
                          maxLines: 1,
                          overflow: .ellipsis,
                        ),
                        onPressed: () => _openOutput(output),
                      ),
                  ],
                ),
              ),
            if (active)
              Row(
                mainAxisAlignment: .end,
                children: [
                  TextButton(
                    onPressed: _discard,
                    child: Text(l10n.refraEditDiscard),
                  ),
                  TextButton(
                    onPressed: _moveBack,
                    child: Text(l10n.refraEditMoveBack),
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  session.status == RefraEditSessionStatus.moved ? l10n.refraEditStatusMoved : l10n.refraEditStatusDiscarded,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOutput(RefraEditOutput output) async {
    final entries = await localMediaDb.loadEntriesByUris({output.uri});
    final entry = entries.firstOrNull;
    if (entry == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EntryViewerPage(initialEntry: entry)),
    );
  }

  Future<void> _moveBack() async {
    final l10n = context.l10n;
    final session = widget.session;
    final outputs = _outputs ?? await refraEditService.refreshOutputs(session);
    final conflicts = await _conflictingNames(session, outputs);
    var strategy = NameConflictStrategy.rename;
    if (conflicts.isNotEmpty) {
      final choice = await showDialog<NameConflictStrategy>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.refraEditConflictTitle),
          content: Text(l10n.refraEditConflictBody(conflicts.length, session.sourceDirectory)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancelTooltip),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(NameConflictStrategy.rename),
              child: Text(l10n.nameConflictStrategyRename),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(NameConflictStrategy.replace),
              child: Text(l10n.nameConflictStrategyReplace),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      strategy = choice;
    }
    final success = await refraEditService.moveBack(session, nameConflictStrategy: strategy);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refraEditMoveBackFailed)));
      return;
    }
    widget.onChanged();
    await _loadOutputs();
  }

  Future<Set<String>> _conflictingNames(RefraEditSession session, List<RefraEditOutput> outputs) async {
    if (session.sourceDirectory.isEmpty) return {};
    final existing = await localMediaDb.loadEntries(directory: session.sourceDirectory);
    final names = existing.map((e) => e.fileNameWithoutExtension).whereType<String>().toSet();
    return outputs.map((o) => pContext.basenameWithoutExtension(o.fileName)).where(names.contains).toSet();
  }

  Future<void> _discard() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.refraEditDiscardConfirmTitle),
        content: Text(l10n.refraEditDiscardConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancelTooltip)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.refraEditDiscard)),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await refraEditService.discard(widget.session);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refraEditDiscardFailed)));
      return;
    }
    widget.onChanged();
  }
}
