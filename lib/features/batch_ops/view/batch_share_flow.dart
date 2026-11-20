import 'package:aves/features/batch_ops/model/batch_result.dart';
import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/view/batch_run_sheet.dart';
import 'package:aves/features/batch_ops/view/batch_share_intro_dialog.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart';

/// Entry point for the copy & share action.
///
/// The explainer runs once per install, before the sheet, so the user knows the
/// output is a temporary copy before configuring anything. Dismissing it does
/// not start a run: the sheet is the next step, and it can still be cancelled.
Future<void> startBatchShare(BuildContext context, Set<AvesEntry> entries) async {
  final l10n = context.l10n;
  if (!entries.any((entry) => entry.isImage && !entry.isRaw)) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.batchShareNoImageFeedback)));
    return;
  }

  await batchSettings.ensureLoaded();
  if (!context.mounted) return;
  if (!await batchSettings.hasSeenShareIntro()) {
    if (!context.mounted) return;
    final proceed = await showBatchShareIntroDialog(context);
    await batchSettings.markShareIntroSeen();
    if (!proceed || !context.mounted) return;
  }
  await startBatch(context, entries, kind: BatchProfileKind.share);
}
