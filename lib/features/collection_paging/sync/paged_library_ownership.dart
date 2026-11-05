import 'package:aves/model/source/collection_source.dart';

/// Whether the windowed engine, rather than the in-memory source, owns the
/// library behind [source].
///
/// The attached summary provider is the one synchronous signal for that: it is
/// mounted by the paging slice on every resolve (`attachPagedSummaries`) and
/// cleared when a view morphs back to the legacy engine. `allowFullLoad()`
/// answers a different question (what memory can afford), so it cannot be asked
/// from a synchronous callback such as a MediaStore observer.
bool pagedLibraryOwnsSource(CollectionSource source) => source.summaries != null;
