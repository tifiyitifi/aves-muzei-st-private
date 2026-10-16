import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/source/section_keys.dart';

/// Stand-in for an entry whose row has not been loaded (yet).
///
/// Skeletons occupy unloaded positions so the sliver geometry stays exact
/// while windows fetch in the background. They carry just enough section
/// context for the scroll-thumb labels (directory, date, rating); every other
/// surface treats them as inert:
///
/// - the tile builder renders a shimmer instead of a thumbnail,
/// - [toSelectableItems] is empty, so no selection path can pick them up,
/// - they are cached per section by the lens and disposed with it, so they
///   never accumulate.
///
/// Skeletons never reach the database, the viewer, or any action: tiles for
/// skeletons are inert, and [PagedCollectionLens.copyWith] only passes loaded
/// real entries to the viewer.
class SkeletonEntry extends AvesEntry {
  /// Section this placeholder stands in, for label rendering.
  final SectionKey sectionKey;

  final DateTime? stampedDate;

  final String? stampedDirectory;

  final int stampedRating;

  new _({
    required this.sectionKey,
    this.stampedDate,
    this.stampedDirectory,
    this.stampedRating = 0,
  }) : super(
          id: -1,
          uri: '',
          path: null,
          contentId: null,
          pageId: null,
          sourceMimeType: '',
          width: 0,
          height: 0,
          sourceRotationDegrees: 0,
          sizeBytes: 0,
          sourceTitle: null,
          dateAddedSecs: null,
          dateModifiedMillis: null,
          sourceDateTakenMillis: null,
          durationMillis: 0,
          trashed: false,
          origin: 0,
        );

  /// One shared placeholder per section: identity never matters (positions do),
  /// so a single instance covers every unloaded row of the section.
  factory forAlbum(String? directory, EntryAlbumSectionKey key) => SkeletonEntry._(sectionKey: key, stampedDirectory: directory);

  factory forMonth(int year, int month, EntryDateSectionKey key) => SkeletonEntry._(sectionKey: key, stampedDate: DateTime(year, month));

  factory forDay(int year, int month, int day, EntryDateSectionKey key) => SkeletonEntry._(sectionKey: key, stampedDate: DateTime(year, month, day));

  factory forRating(int rating, EntryRatingSectionKey key) => SkeletonEntry._(sectionKey: key, stampedRating: rating);

  factory forSingle(SectionKey key) => SkeletonEntry._(sectionKey: key);

  /// Skeletons are never selectable.
  @override
  Set<AvesEntry> toSelectableItems() => const {};

  @override
  DateTime? get bestDate => stampedDate;

  @override
  String? get directory => stampedDirectory;

  @override
  int get rating => stampedRating;
}
