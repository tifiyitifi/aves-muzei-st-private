import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The bar shown when a copy & share run finishes.
///
/// The run never opens the system share sheet: the user may want to review the
/// copies first, or share only some of them, so the bar links to the folder and
/// the sharing stays an explicit second step.
SnackBar batchShareDoneSnackBar(BuildContext context, int count, {required VoidCallback onView}) {
  final l10n = context.l10n;
  return SnackBar(
    content: Text(l10n.batchShareReady(count)),
    action: SnackBarAction(
      label: l10n.batchViewResults,
      onPressed: onView,
    ),
  );
}
