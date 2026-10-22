import 'dart:async';

import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/keys.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/image_op_events.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:test/fake.dart';

class FakeMediaStoreService extends Fake implements MediaStoreService {
  Set<AvesEntry> entries = {};
  Duration? latency;

  /// When set, `getEntries` streams this instead of [entries], so a test can
  /// hold the stream open and observe the states in between.
  Stream<AvesEntry>? entriesStream;

  /// How many times the library stream was asked for. A failed import must not
  /// be restarted behind the user's back, and this is how a test proves it.
  int entryRequestCount = 0;

  /// The last `directory` a stream was asked for, for a caller that must prove
  /// it scoped the query to one folder.
  String? lastRequestedDirectory;

  /// When set, `getEntries` honors `directory` the way the native provider
  /// does. Off by default: the legacy load walks the library one directory at a
  /// time and its tests seed a single entry set, so filtering by default would
  /// starve them.
  bool honorDirectory = false;

  /// When set, `countEntries` fails instead of answering. The platform count is
  /// best-effort in the app, and a test needs the "cannot tell" answer it
  /// produces on a timeout.
  Object? countError;

  /// When set, `countEntries` answers this instead of the row count. The real
  /// provider answers 0 on any query failure, which is indistinguishable from a
  /// genuinely empty library: a test needs both readings.
  int? countAnswer;

  /// How many pages were asked for, and with what. The browse-only timeline is
  /// read a page at a time, and a test proves it by reading the cursor back.
  int pageRequestCount = 0;
  int? lastPageLimit;
  String? lastPageDirectory;
  int? lastPageBeforeSortDateSecs;
  int? lastPageBeforeId;
  int? lastPageBeforeVideoSortDateSecs;
  int? lastPageBeforeVideoId;

  /// When set, `getMediaPage` fails. A read that broke is not an empty library,
  /// and the surface has to be able to tell them apart.
  Object? pageError;

  /// When set, `getMediaPage` waits on it before answering, so a test can hold a
  /// page in flight.
  Completer<void>? pageHold;

  /// Pages answered with no rows but a moved cursor, the way the platform
  /// filters a whole page out. The window must read past them.
  int emptyPages = 0;

  /// With [emptyPages], answer the cursor that was asked for again: a page that
  /// cannot advance has to stop with an error instead of asking forever.
  bool emptyPageCursorStalls = false;

  /// When set, `getAlbumSummaries` fails.
  Object? albumError;

  int albumSummaryRequestCount = 0;

  /// Folder summaries the fake answers. Unset means "derive them from
  /// [entries]", which is what the app's own reads produce.
  List<MediaStoreAlbumSummary>? albumSummaries;

  void reset() {
    entries = {};
    entriesStream = null;
    latency = null;
    entryRequestCount = 0;
    lastRequestedDirectory = null;
    honorDirectory = false;
    countError = null;
    countAnswer = null;
    pageRequestCount = 0;
    lastPageLimit = null;
    lastPageDirectory = null;
    lastPageBeforeSortDateSecs = null;
    lastPageBeforeId = null;
    lastPageBeforeVideoSortDateSecs = null;
    lastPageBeforeVideoId = null;
    pageError = null;
    pageHold = null;
    emptyPages = 0;
    emptyPageCursorStalls = false;
    albumError = null;
    albumSummaryRequestCount = 0;
    albumSummaries = null;
  }

  @override
  Future<List<int>> checkObsoleteContentIds(List<int?> knownContentIds) async {
    if (latency != null) await Future.delayed(latency!);
    return [];
  }

  @override
  Future<List<int>> checkObsoletePaths(Map<int?, String?> knownPathById) async {
    if (latency != null) await Future.delayed(latency!);
    return [];
  }

  @override
  Future<Map<String, int>?> getGenerationByVolume() async {
    if (latency != null) await Future.delayed(latency!);
    return null;
  }

  @override
  Stream<AvesEntry> getEntries(Map<int?, int?> knownEntries, {String? directory}) {
    entryRequestCount++;
    lastRequestedDirectory = directory;
    final stream = entriesStream;
    if (stream != null) return stream;
    // The native provider filters a directory query by the file's parent; the
    // fake does too when a test asks for it (see [honorDirectory]).
    final source = honorDirectory && directory != null ? entries.where((entry) => entry.directory == directory) : entries;
    return Stream.fromIterable(source);
  }

  @override
  Future<int> countEntries() async {
    final error = countError;
    if (error != null) throw error;
    final answer = countAnswer;
    if (answer != null) return answer;
    return entries.length;
  }

  @override
  Future<MediaStorePage> getMediaPage({
    required int limit,
    MediaStorePageCursor? before,
    String? directory,
  }) async {
    pageRequestCount++;
    lastPageLimit = limit;
    lastPageDirectory = directory;
    lastPageBeforeSortDateSecs = before?.images?.sortDateSecs;
    lastPageBeforeId = before?.images?.id;
    lastPageBeforeVideoSortDateSecs = before?.videos?.sortDateSecs;
    lastPageBeforeVideoId = before?.videos?.id;
    final hold = pageHold;
    if (hold != null) await hold.future;
    final error = pageError;
    if (error != null) throw error;

    final source = honorDirectory && directory != null ? entries.where((entry) => entry.directory == directory) : entries;
    // Images and videos are two collections with independent `_ID` spaces, and
    // each is read and bounded on its own, exactly like the platform side.
    final images = source.where((entry) => !_isVideo(entry));
    final videos = source.where(_isVideo);
    final imagePage = _pageOf(images, before?.images, limit);
    final videoPage = _pageOf(videos, before?.videos, limit);

    final candidates = [...imagePage.rows, ...videoPage.rows]..sort(_compareNewestFirst);
    final page = candidates.take(limit).toList();
    // One cursor per collection: the last row the page took from it. A
    // collection with nothing taken keeps its cursor, unless it read rows and
    // kept none (the platform filtered them), in which case it moves on.
    AvesEntry? lastImage, lastVideo;
    for (final entry in page) {
      if (_isVideo(entry)) {
        lastVideo = entry;
      } else {
        lastImage = entry;
      }
    }
    final cursor = MediaStorePageCursor(
      images: lastImage != null ? _keyOf(lastImage) : (imagePage.rows.isEmpty ? imagePage.rawLast ?? before?.images : before?.images),
      videos: lastVideo != null ? _keyOf(lastVideo) : (videoPage.rows.isEmpty ? videoPage.rawLast ?? before?.videos : before?.videos),
    );
    if (emptyPages > 0) {
      // The platform looked at a page and kept none of its rows. Its cursor
      // moved, so the window reads the rows behind it; a stalled cursor must
      // make the window stop with an error rather than loop.
      emptyPages--;
      return MediaStorePage(
        entries: const [],
        hasMore: true,
        cursor: emptyPageCursorStalls ? MediaStorePageCursor(images: before?.images, videos: before?.videos) : cursor,
      );
    }
    return MediaStorePage(
      entries: page,
      hasMore: imagePage.truncated || videoPage.truncated || candidates.length > limit,
      cursor: cursor,
    );
  }

  static bool _isVideo(AvesEntry entry) => entry.sourceMimeType.startsWith('video/');

  static int _sortDateSecs(AvesEntry entry) =>
      // The three dates the platform sorts by, in the same order: capture, then
      // modification, then addition.
      (entry.sourceDateTakenMillis ?? entry.dateModifiedMillis ?? (entry.dateAddedSecs ?? 0) * 1000) ~/ 1000;

  static MediaStorePageKey _keyOf(AvesEntry entry) => MediaStorePageKey(sortDateSecs: _sortDateSecs(entry), id: entry.contentId ?? 0);

  static int _compareNewestFirst(AvesEntry a, AvesEntry b) {
    final c = _sortDateSecs(b).compareTo(_sortDateSecs(a));
    return c != 0 ? c : (b.contentId ?? 0).compareTo(a.contentId ?? 0);
  }

  /// One collection's page: at most [limit] rows after [before], plus the raw
  /// last row it read, so a page that filters every row out still advances.
  static _FakePage _pageOf(Iterable<AvesEntry> rows, MediaStorePageKey? before, int limit) {
    final sorted = rows.where((entry) {
      if (before == null) return true;
      final date = _sortDateSecs(entry);
      final id = entry.contentId ?? 0;
      return date < before.sortDateSecs || (date == before.sortDateSecs && id < before.id);
    }).toList()..sort(_compareNewestFirst);
    final page = sorted.take(limit).toList();
    return _FakePage(page, sorted.length >= limit, page.isEmpty ? null : _keyOf(page.last));
  }

  @override
  Future<List<MediaStoreAlbumSummary>> getAlbumSummaries() async {
    albumSummaryRequestCount++;
    final error = albumError;
    if (error != null) throw error;
    final configured = albumSummaries;
    if (configured != null) return configured;

    final buckets = <String, List<AvesEntry>>{};
    for (final entry in entries) {
      final directory = entry.directory;
      if (directory == null || directory.isEmpty) continue;
      buckets.putIfAbsent(directory, () => []).add(entry);
    }
    return [
      for (final bucket in buckets.entries)
        MediaStoreAlbumSummary(
          directory: bucket.key,
          count: bucket.value.length,
          sizeBytes: bucket.value.fold(0, (sum, row) => sum + (row.sizeBytes ?? 0)),
          cover: bucket.value.reduce((a, b) => (a.bestDate?.millisecondsSinceEpoch ?? 0) >= (b.bestDate?.millisecondsSinceEpoch ?? 0) ? a : b),
        ),
    ];
  }

  static var _lastId = 1;

  static int get nextId => _lastId++;

  static int get dateMillis => DateTime.now().millisecondsSinceEpoch;

  static AvesEntry newImage(String album, String fileNameWithoutExtension, {int? id, int? contentId}) {
    id ??= nextId;
    contentId ??= id;
    final _dateMillis = dateMillis;
    final _dateSecs = _dateMillis ~/ 1000;
    return AvesEntry(
      origin: EntryOrigins.mediaStoreContent,
      id: id,
      uri: 'content://media/external/images/media/$contentId',
      path: '$album/$fileNameWithoutExtension.jpg',
      contentId: contentId,
      pageId: null,
      sourceMimeType: MimeTypes.jpeg,
      width: 360,
      height: 720,
      sourceRotationDegrees: 0,
      sizeBytes: 42,
      sourceTitle: fileNameWithoutExtension,
      dateAddedSecs: _dateSecs,
      dateModifiedMillis: _dateMillis,
      sourceDateTakenMillis: _dateMillis,
      durationMillis: null,
      trashed: false,
    );
  }

  static MoveOpEvent moveOpEventForMove(AvesEntry entry, String sourceAlbum, String destinationAlbum) {
    final newContentId = nextId;
    return MoveOpEvent(
      success: true,
      skipped: false,
      uri: entry.uri,
      newFields: {
        EntryFields.uri: 'content://media/external/images/media/$newContentId',
        EntryFields.contentId: newContentId,
        EntryFields.path: entry.path!.replaceFirst(sourceAlbum, destinationAlbum),
        EntryFields.dateModifiedMillis: FakeMediaStoreService.dateMillis,
      },
      deleted: false,
    );
  }

  static MoveOpEvent moveOpEventForRename(AvesEntry entry, String newName) {
    final newContentId = nextId;
    final oldName = entry.fileNameWithoutExtension!;
    return MoveOpEvent(
      success: true,
      skipped: false,
      uri: entry.uri,
      newFields: {
        EntryFields.uri: 'content://media/external/images/media/$newContentId',
        EntryFields.contentId: newContentId,
        EntryFields.path: entry.path!.replaceFirst(oldName, newName),
        EntryFields.dateModifiedMillis: FakeMediaStoreService.dateMillis,
      },
      deleted: false,
    );
  }
}

/// What one fake collection read returned, mirroring the platform page: the rows
/// it kept and the last row it read, filtered or not.
class _FakePage {
  final List<AvesEntry> rows;
  final bool truncated;
  final MediaStorePageKey? rawLast;

  const new(this.rows, this.truncated, this.rawLast);
}
