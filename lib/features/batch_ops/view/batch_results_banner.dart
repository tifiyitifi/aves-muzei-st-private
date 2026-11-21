import 'dart:async';

import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_results_service.dart';
import 'package:aves/features/batch_ops/view/batch_results_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The decisions offered while browsing the batch results folder.
///
/// It only appears when the folder itself is the current view, so the actions
/// are always about the files the user is looking at. "Not now" keeps every row
/// pending; nothing is applied without an explicit tap.
class BatchResultsBannerSliver extends StatefulWidget {
  final BatchResultsService service;

  const new({super.key, this.service = batchResultsService});

  @override
  State<BatchResultsBannerSliver> createState() => _BatchResultsBannerSliverState();
}

class _BatchResultsBannerSliverState extends State<BatchResultsBannerSliver> {
  List<BatchResult>? _pending;
  bool _dismissed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await widget.service.pruneMissingResults();
    final store = await widget.service.store();
    final pending = await store.getPending();
    if (!mounted) return;
    setState(() => _pending = pending);
  }

  Future<void> _replace() async {
    final l10n = context.l10n;
    final targets = _pending ?? const <BatchResult>[];
    if (targets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.batchResultsReplaceConfirmTitle),
        content: Text(l10n.batchResultsReplaceConfirmBody(targets.length)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancelTooltip)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.applyButtonLabel)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final replaced = await widget.service.replaceWithSource(targets);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(replaced > 0 ? l10n.batchResultsReplaced(replaced) : l10n.batchResultsActionFailed)),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveBack() async {
    final l10n = context.l10n;
    final targets = _pending ?? const <BatchResult>[];
    if (targets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.batchResultsMoveBackConfirmTitle),
        content: Text(l10n.batchResultsMoveBackConfirmBody(targets.length)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancelTooltip)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.applyButtonLabel)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final moved = await widget.service.moveBack(targets);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(moved > 0 ? l10n.batchResultsMoved(moved) : l10n.batchResultsActionFailed)),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manage() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BatchResultsPage()));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pending = _pending;
    if (_dismissed || pending == null || pending.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_motion, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.batchResultsWaitingCount(pending.length), style: theme.textTheme.titleMedium)),
                  if (_busy)
                    const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      icon: const Icon(Icons.tune),
                      tooltip: l10n.batchResultsManage,
                      onPressed: _manage,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(onPressed: _busy ? null : _replace, child: Text(l10n.batchResultsReplace)),
                  OutlinedButton(onPressed: _busy ? null : _moveBack, child: Text(l10n.batchResultsMoveBack)),
                  TextButton(
                    onPressed: () => setState(() => _dismissed = true),
                    child: Text(l10n.batchResultsNotNow),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
