import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Whether an entry-set action cannot be served at all, saying so when it cannot.
///
/// The filter grids collect their targets from the in-memory source. A library
/// too large to load holds no entries, so an action over it would act on nothing
/// (or on whatever happened to be loaded) without a word: report it instead,
/// exactly like a view that needs every item.
///
/// Answers true when the caller must stop. The probe is the same one every
/// full-load path asks, so an explicit legacy engine never trips it.
Future<bool> pagedScopeUnsupported(BuildContext context) async {
  if (await const CollectionEngineRouter().allowFullLoad()) return false;
  if (!context.mounted) return true;
  await showWarningDialog(
    context: context,
    message: context.l10n.collectionPagedUnsupportedAction,
  );
  return true;
}
