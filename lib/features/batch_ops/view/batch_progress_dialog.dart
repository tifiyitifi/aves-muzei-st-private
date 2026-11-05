import 'package:aves/features/batch_ops/services/batch_run_controller.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart';

/// Live progress for one batch job.
///
/// The dialog owns no controller: the caller creates and disposes it, so closing
/// the dialog can never cancel a job that the native side is still writing.
class BatchProgressDialog extends StatelessWidget {
  final BatchRunController controller;

  const new({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.batchProgressTitle),
      content: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          final total = controller.total;
          final processed = controller.done + controller.failed;
          final summary = switch (controller.state) {
            BatchRunState.done => l10n.batchDoneSummary(controller.done, total),
            BatchRunState.cancelled => l10n.batchCancelledSummary(controller.done, total),
            _ => l10n.batchProgressSummary(controller.done, total, controller.failed),
          };
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: total > 0 ? processed / total : null),
              const SizedBox(height: 12),
              Text(summary),
            ],
          );
        },
      ),
      actions: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            if (controller.isRunning) {
              return TextButton(
                onPressed: controller.cancel,
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              );
            }
            return TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            );
          },
        ),
      ],
    );
  }
}
