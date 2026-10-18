import 'package:aves/features/drift_db/app_meta/app_meta_store.dart';
import 'package:aves/model/db/db.dart';

/// The catalog sweep's resume position, in the generic `appMeta` table.
///
/// Stored as plain text (`directory` newline `id`), so a hand-edited or corrupt
/// value degrades to "start from the beginning" instead of failing the sweep.
/// The position is what makes repeated short runs fair: a sweep that stops when
/// the user leaves resumes at its frontier and wraps to cover the rest, instead
/// of re-walking the head of a huge backlog every time.
class CatalogCursorStore {
  static const _key = 'catalogCursor';

  final AppMetaStore appMeta;

  new(this.appMeta);

  Future<BacklogCursor?> read() async {
    final raw = (await appMeta.read({_key}))[_key];
    if (raw == null) return null;
    final separator = raw.indexOf('\n');
    if (separator < 0) return null;
    final id = int.tryParse(raw.substring(separator + 1));
    if (id == null) return null;
    return (directory: raw.substring(0, separator), id: id);
  }

  Future<void> write(BacklogCursor cursor) => appMeta.write({_key: '${cursor.directory}\n${cursor.id}'});
}
