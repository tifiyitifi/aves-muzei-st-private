import 'package:aves/features/batch_ops/services/batch_settings.dart';
import 'package:aves/features/batch_ops/view/batch_share_settings_page.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Why copy & share writes its own folder, shown once per install.
///
/// The explanation is deliberately concrete: share output is a temporary copy,
/// not a backup, and it is cleaned automatically. Dismissing the dialog does not
/// start a run; the user has to choose to continue.
Future<bool> showBatchShareIntroDialog(BuildContext context, {String? confirmLabel}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => _BatchShareIntroDialog(confirmLabel: confirmLabel),
  );
  return proceed == true;
}

class _BatchShareIntroDialog extends StatelessWidget {
  final String? confirmLabel;

  const new({this.confirmLabel});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.batchShareIntroTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.batchShareIntroBody),
            const SizedBox(height: 12),
            // The dialog can open the settings page, so the retention sentence
            // must follow a change made there.
            ListenableBuilder(
              listenable: batchSettings,
              builder: (context, _) {
                final days = batchSettings.shareRetentionDays;
                return Text(days > 0 ? l10n.batchShareIntroRetention(days) : l10n.batchShareIntroKeep);
              },
            ),
            const SizedBox(height: 12),
            Text(l10n.batchShareIntroNotBackup),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: BatchShareSettingsPage.routeName),
              builder: (_) => const BatchShareSettingsPage(),
            ),
          ),
          child: Text(l10n.batchShareIntroSettings),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? l10n.batchShareIntroContinue),
        ),
      ],
    );
  }
}
