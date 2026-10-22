import 'package:aves/features/browse_only/services/browse_library.dart';

/// One album's rows, read from the media store on demand.
///
/// The album list is whole, but its rows are not held anywhere: opening a folder
/// reads exactly that folder, a page at a time, so a huge album stays bounded by
/// its own size instead of the library's. The rows land in a [BrowseLibrary],
/// which gives the album the same ordering, month sections and on-demand entry
/// materialization as the timeline.
class BrowseAlbumLoader {
  final String directory;
  final BrowseLibrary library;

  new({required this.directory}) : library = BrowseLibrary(directory: directory);

  /// Reads the folder whole: the first page paints, the rest follows, the way
  /// the folder's count is already whole when the album is opened.
  Future<void> load() => library.loadAll();

  void dispose() => library.dispose();
}
