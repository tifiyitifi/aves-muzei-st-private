import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/collection_lens.dart';
import 'package:aves/model/source/collection_source.dart';

/// The lens the browser hands to the viewer.
///
/// The rows come from the media store, not from the catalogued source: a source
/// refresh, a removal or a metadata event during the import must not reshape the
/// set the user is swiping through, so the lens does not follow the source and
/// its fixed selection is the whole truth for it.
CollectionLens browseViewerLens(CollectionSource source, List<AvesEntry> entries) =>
    CollectionLens(source: source, listenToSource: false, fixedSelection: entries);
