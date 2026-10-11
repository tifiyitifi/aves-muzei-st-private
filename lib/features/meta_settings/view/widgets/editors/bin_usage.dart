import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/vaults/vaults.dart';
import 'package:aves/widgets/collection/entry_set_action_delegate.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Fork-owned copy of the bin-usage teardown, used when the TV layout is enabled
/// (which requires the bin to be off).
///
/// Mirrors the upstream privacy tile so the v2 surface never imports the
/// upstream settings layer.
Future<bool> setBinUsage(BuildContext context, bool enabled) async {
  final l10n = context.l10n;
  if (!enabled) {
    if (vaults.all.any((v) => v.useBin)) {
      await showWarningDialog(
        context: context,
        message: l10n.vaultBinUsageDialogMessage,
      );
      return false;
    }

    final source = context.read<CollectionSource>();
    final trashedEntries = source.trashedEntries;
    if (trashedEntries.isNotEmpty) {
      if (!await showConfirmationDialog(
        context: context,
        message: l10n.settingsDisablingBinWarningDialogMessage,
        ok: l10n.applyButtonLabel,
      )) {
        return false;
      }

      // delete forever trashed items
      await EntrySetActionDelegate().doDelete(
        context: context,
        entries: trashedEntries,
        enableBin: false,
      );

      // in case of failure or cancellation
      if (source.trashedEntries.isNotEmpty) return false;
    }

    settings.searchHistory = [];
  }

  settings.enableBin = enabled;
  return true;
}
