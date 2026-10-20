import 'package:aves/features/browse_only/services/browse_library.dart';
import 'package:aves/features/collection_paging/import/import_rows.dart';

/// Connects the browse index to the import that feeds it.
///
/// Called once by the collection page, before the lens starts its first import:
/// the rows then reach the browser in the same pass that writes them, so a
/// fresh install never scans MediaStore twice.
void installBrowseOnly() {
  importRowsSink = browseLibrary.addEntries;
}
