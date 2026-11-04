import 'dart:async';

import 'package:aves/features/refra_edit/log.dart';
import 'package:aves/features/refra_edit/services/refra_edit_service.dart';
import 'package:aves/features/refra_edit/view/refra_edit_intro_dialog.dart';
import 'package:aves/features/refra_edit/view/refra_edit_sessions_page.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/material.dart';

/// Entry point of the copy-first edit flow.
///
/// The original file is never handed to an editor: the source is copied into
/// `Pictures/aves_refra_edit/<sessionId>` first, and only that copy is opened. The chooser runs
/// before the copy so cancelling it leaves no files behind.
Future<void> startRefraEdit(BuildContext context, AvesEntry entry) async {
  final l10n = context.l10n;
  const service = refraEditService;

  if (!await service.hasSeenIntro()) {
    if (!context.mounted) return;
    await showRefraEditIntroDialog(context);
    await service.markIntroSeen();
  }
  if (!context.mounted) return;

  final choice = await showRefraEditorChooser(context);
  if (choice == null || !context.mounted) return;

  // Captured before the editor opens: the page that started the flow may be gone by the time it
  // returns, and the result feedback must still reach the user.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  try {
    final session = await service.createSession(entry);
    final saved = switch (choice) {
      RefraEditorChoice.builtIn => await service.openBuiltIn(session),
      RefraEditorChoice.otherApp => await service.openExternal(session),
    };
    if (!saved) return;
    // Saving never touches the original, so tell the user where the copy went instead of letting
    // the editor simply disappear.
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l10n.refraEditSaved),
        action: SnackBarAction(
          label: l10n.showButtonLabel,
          onPressed: () {
            unawaited(
              navigator.push(
                MaterialPageRoute(builder: (_) => const RefraEditSessionsPage()),
              ),
            );
          },
        ),
      ),
    );
  } catch (error) {
    refraEditLog.e('failed to start a session for ${entry.uri}', error);
    messenger?.showSnackBar(SnackBar(content: Text(l10n.refraEditCopyFailed)));
  }
}
