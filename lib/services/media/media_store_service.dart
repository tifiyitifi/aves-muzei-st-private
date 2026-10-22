import 'dart:async';

import 'package:aves/model/entry/entry.dart';
import 'package:aves/services/common/channel.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/services.dart';

abstract class MediaStoreService {
  Future<List<int>> checkObsoleteContentIds(List<int?> knownContentIds);

  Future<List<int>> checkObsoletePaths(Map<int?, String?> knownPathById);

  Future<List<String>> getChangedUris(Map<String, int?> sinceGenerationByVolume);

  Future<Map<String, int>?> getGenerationByVolume();

  // knownEntries: map of contentId -> dateModifiedMillis
  Stream<AvesEntry> getEntries(Map<int?, int?> knownEntries, {String? directory});

  /// Counts the rows [getEntries] would stream for the whole library.
  ///
  /// Used as the denominator of the one-time import progress: the database
  /// cannot know it before the rows are written. 0 when the platform cannot
  /// tell, which callers render as "unknown" instead of blocking.
  Future<int> countEntries();

  /// One bounded page of media rows, newest first, for the browse-only surface.
  ///
  /// [beforeSortDateSecs] and [beforeId] are the last row of the previous page,
  /// so the read resumes after it instead of walking everything newer.
  /// [directory] scopes the page to one folder, for an album's contents.
  ///
  /// This is not [getEntries]: the rows arrive in one reply, without the file
  /// stats and embedded probes the import pays for, which is what makes a first
  /// screen a bounded query instead of a whole-library pass.
  Future<MediaStorePage> getMediaPage({
    required int limit,
    int? beforeSortDateSecs,
    int? beforeId,
    String? directory,
  });

  /// Every folder the media store reports, with its count, size and cover row.
  ///
  /// The rows are counted on the platform side: this is the album list as a
  /// whole, not a stream a caller aggregates from.
  Future<List<MediaStoreAlbumSummary>> getAlbumSummaries();

  // returns media URI
  Future<Uri?> scanFile(String path, String mimeType);
}

/// One page of [MediaStoreService.getMediaPage].
class MediaStorePage {
  final List<AvesEntry> entries;

  /// Whether the page was cut: rows exist behind it.
  final bool hasMore;

  const new({required this.entries, required this.hasMore});
}

/// One folder of [MediaStoreService.getAlbumSummaries].
class MediaStoreAlbumSummary {
  /// The folder path, without a trailing separator.
  final String directory;

  /// Rows the media store reports for the folder.
  final int count;

  final int sizeBytes;

  /// The folder's newest row, for the tile.
  final AvesEntry cover;

  const new({
    required this.directory,
    required this.count,
    required this.sizeBytes,
    required this.cover,
  });
}

class PlatformMediaStoreService implements MediaStoreService {
  static const _platform = AvesMethodChannel('deckers.thibault/aves/media_store');
  static final _stream = AvesStreamsChannel('deckers.thibault/aves/media_store_stream');

  @override
  Future<List<int>> checkObsoleteContentIds(List<int?> knownContentIds) async {
    try {
      final result = await _platform.invokeMethod('checkObsoleteContentIds', <String, Object?>{
        'knownContentIds': knownContentIds,
      });
      return (result as List).cast<int>();
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
    }
    return [];
  }

  @override
  Future<List<int>> checkObsoletePaths(Map<int?, String?> knownPathById) async {
    try {
      final result = await _platform.invokeMethod('checkObsoletePaths', <String, Object?>{
        'knownPathById': knownPathById,
      });
      return (result as List).cast<int>();
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
    }
    return [];
  }

  @override
  Future<List<String>> getChangedUris(Map<String, int?> sinceGenerationByVolume) async {
    try {
      final result = await _platform.invokeMethod('getChangedUris', <String, Object?>{
        'sinceGenerationByVolume': sinceGenerationByVolume,
      });
      return (result as List).cast<String>();
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
    }
    return [];
  }

  @override
  Future<Map<String, int>?> getGenerationByVolume() async {
    try {
      var result = await _platform.invokeMethod('getGenerationByVolume');
      if (result != null) return (result as Map).cast<String, int>();
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
    }
    return null;
  }

  @override
  Future<int> countEntries() async {
    try {
      final result = await _platform.invokeMethod('countEntries');
      if (result is int) return result;
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
    }
    return 0;
  }

  @override
  Future<MediaStorePage> getMediaPage({
    required int limit,
    int? beforeSortDateSecs,
    int? beforeId,
    String? directory,
  }) async {
    try {
      final result = await _platform.invokeMethod('getMediaPage', <String, Object?>{
        'limit': limit,
        'beforeSortDateSecs': beforeSortDateSecs,
        'beforeId': beforeId,
        'directory': directory,
      });
      if (result is Map) {
        return MediaStorePage(
          entries: _entriesOf(result['rows']),
          hasMore: result['hasMore'] == true,
        );
      }
      return const MediaStorePage(entries: [], hasMore: false);
    } on PlatformException catch (e, stack) {
      // A failed page is not an empty library: the caller has to be able to tell
      // the two apart before it reports the end of the timeline.
      await reportService.recordError(e, stack);
      rethrow;
    }
  }

  @override
  Future<List<MediaStoreAlbumSummary>> getAlbumSummaries() async {
    try {
      final result = await _platform.invokeMethod('getAlbumSummaries');
      if (result is! List) return const [];
      final summaries = <MediaStoreAlbumSummary>[];
      for (final item in result) {
        if (item is! Map) continue;
        final directory = item['directory'];
        final cover = item['cover'];
        if (directory is! String || cover is! Map) continue;
        final entry = _entryOf(cover);
        // A folder without a row to show has no tile: leaving it out beats
        // rendering a grid cell that cannot paint.
        if (entry == null) continue;
        summaries.add(
          MediaStoreAlbumSummary(
            directory: directory,
            count: (item['count'] as num?)?.toInt() ?? 0,
            sizeBytes: (item['sizeBytes'] as num?)?.toInt() ?? 0,
            cover: entry,
          ),
        );
      }
      return summaries;
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
      rethrow;
    }
  }

  static List<AvesEntry> _entriesOf(Object? rows) {
    if (rows is! List) return const [];
    final entries = <AvesEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final entry = _entryOf(row);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// One row, or null when it cannot be built from what the platform reported.
  /// A single unparsable row must not cost the whole page.
  static AvesEntry? _entryOf(Map row) {
    try {
      AvesEntry.normalizeMimeTypeFields(row);
      return AvesEntry.fromMap(row);
    } catch (error, stack) {
      unawaited(reportService.recordError(error, stack));
      return null;
    }
  }

  @override
  Stream<AvesEntry> getEntries(Map<int?, int?> knownEntries, {String? directory}) {
    try {
      return _stream
          .receiveBroadcastStream(<String, Object?>{
            'knownEntries': knownEntries,
            'directory': directory,
          })
          .where((event) => event is Map)
          .map<AvesEntry?>((event) {
            final fields = event as Map;
            try {
              AvesEntry.normalizeMimeTypeFields(fields);
              return AvesEntry.fromMap(fields);
            } catch (error, stack) {
              // One unparsable row must not end the stream: a consumer reading
              // it as a whole library (an import, a browse scan) stops at the
              // error and never sees the rows behind it.
              unawaited(reportService.recordError(error, stack));
              return null;
            }
          })
          .where((entry) => entry != null)
          .cast<AvesEntry>();
    } on PlatformException catch (e, stack) {
      reportService.recordError(e, stack);
      return Stream.error(e);
    }
  }

  // returns media URI
  @override
  Future<Uri?> scanFile(String path, String mimeType) async {
    try {
      final result = await _platform.invokeMethod('scanFile', <String, Object?>{
        'path': path,
        'mimeType': mimeType,
      });
      if (result != null) return Uri.tryParse(result);
    } on PlatformException catch (e, stack) {
      await reportService.recordError(e, stack);
    }
    return null;
  }
}
