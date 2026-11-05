import 'dart:async';

import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/services/batch_run_controller.dart';
import 'package:aves/features/batch_ops/view/batch_action_editor.dart';
import 'package:aves/features/batch_ops/view/batch_progress_dialog.dart';
import 'package:aves/features/batch_ops/view/batch_tool_catalog.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart';

/// Entry point for the collection/viewer batch action.
///
/// The sheet only selects and configures actions; the run itself lives in
/// [BatchRunController] so the same flow can later be driven by a saved profile
/// or by copy-share without a UI round trip.
Future<void> startBatch(BuildContext context, Set<AvesEntry> entries) async {
  final images = entries.where((entry) => entry.isImage && !entry.isRaw).toSet();
  if (images.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.batchNoImageFeedback)));
    return;
  }

  final actions = await showBatchRunSheet(context, images.length);
  if (actions == null || actions.isEmpty || !context.mounted) return;

  final controller = BatchRunController();
  unawaited(controller.run(entries: images, actions: actions));
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => BatchProgressDialog(controller: controller),
  );
  controller.dispose();
}

Future<List<BatchAction>?> showBatchRunSheet(BuildContext context, int entryCount) {
  return showModalBottomSheet<List<BatchAction>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => BatchRunSheet(entryCount: entryCount),
  );
}

class BatchRunSheet extends StatefulWidget {
  final int entryCount;

  const new({super.key, required this.entryCount});

  @override
  State<BatchRunSheet> createState() => _BatchRunSheetState();
}

class _BatchRunSheetState extends State<BatchRunSheet> {
  late final List<BatchAction> _actions = batchRunnableCatalog.map((info) => info.createDefault().copyWith(enabled: false)).toList();

  List<BatchAction> get _enabledActions => _actions.where((action) => action.enabled).toList();

  Future<void> _edit(int index) async {
    final edited = await showBatchActionEditor(context, _actions[index]);
    if (edited == null || !mounted) return;
    setState(() => _actions[index] = edited.copyWith(enabled: true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.batchRunSheetTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(l10n.batchRunSheetExplanation),
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
