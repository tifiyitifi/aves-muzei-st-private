import 'package:aves/features/batch_ops/services/batch_run_controller.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Live progress for one batch job.
///
/// The dialog owns no controller: the caller creates and disposes it, so closing
/// the dialog can never cancel a job that the native side is still writing. The
/// caller waits for [BatchRunController.settled] and the pending records after
/// the dialog closes, which is what keeps a dismissed dialog from orphaning the
/// results it could no longer record.
class BatchProgressDialog extends StatelessWidget {
  final BatchRunController controller;

  const new({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => AlertDialog(
        title: Text(l10n.batchProgressTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: controller.total > 0 ? (controller.done + controller.failed) / controller.total : null),
            const SizedBox(height: 12),
            Text(
              switch (controller.state) {
                BatchRunState.done => l10n.batchDoneSummary(controller.done, controller.total),
                BatchRunState.cancelled => l10n.batchCancelledSummary(controller.done, controller.total),
                _ => l10n.batchProgressSummary(controller.done, controller.total, controller.failed),
              },
            ),
          ],
        ),
        actions: [
          if (controller.isRunning)
            TextButton(
              onPressed: controller.cancel,
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
        ],
      ),
    );
  }
}
