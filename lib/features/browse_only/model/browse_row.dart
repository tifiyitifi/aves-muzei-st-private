import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/keys.dart';

/// One MediaStore row, compact enough to keep a whole library in memory.
///
/// A full [AvesEntry] carries change notifiers and mutable metadata per row,
/// and the legacy collection adds every derived map on top of that. Browse-only
/// needs only what the media store itself reports, so it keeps exactly those
/// fields and materializes an entry for the rows a surface actually shows.
class BrowseRow {
  final int id;
  final int? contentId;
  final String uri;
  final String? path;
  final String mimeType;
  final int width, height, rotation;
  final int? sizeBytes;
  final int? dateTakenMillis, dateModifiedMillis, dateAddedSecs, durationMillis;
  final bool trashed;
  final int origin;

  /// Sorting label: what MediaStore calls the item before any cataloguing.
  final String? title;

  /// Folder path, without a trailing separator. The album the row belongs to.
  final String? directory;

  const new({
    required this.id,
    required this.contentId,
    required this.uri,
    required this.path,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.rotation,
    required this.sizeBytes,
    required this.dateTakenMillis,
    required this.dateModifiedMillis,
    required this.dateAddedSecs,
    required this.durationMillis,
    required this.trashed,
    required this.origin,
    required this.directory,
    required this.title,
  });

  factory fromEntry(AvesEntry entry) => BrowseRow(
    id: entry.id,
    contentId: entry.contentId,
    uri: entry.uri,
    path: entry.path,
    mimeType: entry.sourceMimeType,
    width: entry.width,
    height: entry.height,
    rotation: entry.sourceRotationDegrees,
    sizeBytes: entry.sizeBytes,
    dateTakenMillis: entry.sourceDateTakenMillis,
    dateModifiedMillis: entry.dateModifiedMillis,
    dateAddedSecs: entry.dateAddedSecs,
    durationMillis: entry.durationMillis,
    trashed: entry.trashed,
    origin: entry.origin,
    directory: entry.directory,
    title: entry.bestTitle,
  );

  /// The date the browser groups and sorts by, mirroring `AvesEntry.bestDate`
  /// before any cataloguing: capture, then modification, then addition.
  int get bestDateMillis => dateTakenMillis ?? dateModifiedMillis ?? (dateAddedSecs ?? 0) * 1000;

  bool get isVideo => mimeType.startsWith('video/');

  /// A fresh entry for a surface that needs one (grid tile, viewer).
  ///
  /// [id] is the browser's own stable identity for this row: the media store
  /// does not hand out database ids, and two rows must never share one.
  AvesEntry toEntry({required int id}) => AvesEntry.fromMap({
    EntryFields.id: id,
    EntryFields.uri: uri,
    EntryFields.path: path,
    EntryFields.contentId: contentId,
    EntryFields.sourceMimeType: mimeType,
    EntryFields.width: width,
    EntryFields.height: height,
    EntryFields.sourceRotationDegrees: rotation,
    EntryFields.sizeBytes: sizeBytes,
    EntryFields.dateAddedSecs: dateAddedSecs,
    EntryFields.dateModifiedMillis: dateModifiedMillis,
    EntryFields.sourceDateTakenMillis: dateTakenMillis,
    EntryFields.durationMillis: durationMillis,
    EntryFields.trashed: trashed ? 1 : 0,
    EntryFields.origin: origin,
  });
}
