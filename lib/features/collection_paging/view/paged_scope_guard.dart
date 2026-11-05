import 'package:aves/features/collection_paging/engine/collection_engine_router.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Whether an album-grid action must read its entries from the database.
///
/// `allowFullLoad` answers what memory can afford, not whether the source holds
/// entries at all: a paged view keeps its source entry-free even when the
/// library is small enough to load (an explicit paged engine, or a first launch
/// before the import completes). The attached summary provider is the
/// authoritative signal that the page reads the database, so the action must
/// follow it instead of materializing an empty source.
Future<bool> albumActionUsesDatabase(BuildContext context) async {
  if (context.read<CollectionSource>().summaries != null) return true;
  return !await const CollectionEngineRouter().allowFullLoad();
}

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
