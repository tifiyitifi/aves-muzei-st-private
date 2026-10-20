import 'dart:async';
import 'dart:collection';

import 'package:aves/features/browse_only/model/browse_row.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// A folder as the browser lists it: what the album shows and how much of it.
class BrowseAlbum {
  final String directory;

  /// Display name, disambiguated against same-named folders on other paths.
  final String name;
  final int count;

  /// Row index of the newest item, used as the cover.
  final int coverIndex;

  const new({
    required this.directory,
    required this.name,
    required this.count,
    required this.coverIndex,
  });
}

/// One month of rows, for the media grid's sticky headers.
class BrowseMonth {
  final int year, month;

  /// Row indexes, newest first.
  final List<int> indexes;

  const new({
    required this.year,
    required this.month,
    required this.indexes,
  });
}

/// The whole library as browsing needs it, independent of the import.
///
/// Rows arrive from the media store stream (newest first) and are kept in that
/// order, so index 0 is the newest row and appending never reorders what is
/// already on screen. Nothing here touches the database or `CollectionSource`:
/// a partial import cannot make an album empty, and a surface can never read a
/// half-built aggregate.
class BrowseLibrary extends ChangeNotifier {
  /// Materialized entries kept around for the visible rows. Small on purpose:
  /// the compact rows are the index, entries are a rendering detail.
  static const int _entryCacheMax = 600;

  final List<BrowseRow> _rows = [];

  /// Row identity to position, so a resumed import's re-streamed rows do not
  /// duplicate.
  final Map<int, int> _indexByKey = {};

  /// Folder to the positions of its rows, newest first.
  final Map<String, List<int>> _albumRows = {};

  final LinkedHashMap<int, AvesEntry> _entries = LinkedHashMap();

  int _total = 0;
  int _version = 0;
  List<BrowseAlbum>? _albums;
  List<BrowseMonth>? _months;

  /// Display orders, keyed by what they were computed from. A sort change or a
  /// new batch invalidates them; the index itself never moves.
  List<int>? _mediaOrder;
  String _mediaOrderKey = '';
  int _mediaOrderVersion = -1;
  List<BrowseAlbum>? _albumOrder;
  String _albumOrderKey = '';
  int _albumOrderVersion = -1;
  Map<String, int>? _albumDates;
  int _albumDatesVersion = -1;

  /// The hidden-album set the caches were built with: a preferences change has
  /// to show immediately, and the index itself does not change.
  String _albumsHidden = '';
  String _monthsHidden = '';
  bool _disposed = false;
  bool _scanning = false;
  bool _scanStopped = false;
  Future<void>? _scan;

  /// Streams the library straight from MediaStore, for a start where no import
  /// runs (the database is already complete). The surface is only shown until
  /// the collection resolves, so the scan is short-lived and its early batches
  /// are what the first frame paints.
  Future<void> scan() => _scan ??= _scanLibrary();

  /// Stops a scan whose surface is gone (the collection took over).
  void stopScan() {
    _scanStopped = true;
  }

  Future<void> _scanLibrary() async {
    if (_scanning) return;
    _scanning = true;
    _scanStopped = false;
    final stopwatch = Stopwatch()..start();
    try {
      unawaited(
        mediaStoreService.countEntries().then(setTotal, onError: (Object error, StackTrace stack) {
          _log.w('browse-only count failed', error, stack);
        }),
      );
      final buffer = <AvesEntry>[];
      await for (final entry in mediaStoreService.getEntries(const {})) {
        if (_scanStopped) break;
        buffer.add(entry);
        if (buffer.length >= 250) {
          addEntries(buffer);
          buffer.clear();
        }
      }
      if (buffer.isNotEmpty) addEntries(buffer);
      _log.i('browse-only scan indexed $length rows in ${stopwatch.elapsedMilliseconds}ms');
    } catch (error, stack) {
      // Keep what arrived: the collection page takes over either way.
      _log.w('browse-only scan failed', error, stack);
    } finally {
      _scanning = false;
    }
  }

  /// Rows indexed so far.
  int get length => _rows.length;

  /// Rows MediaStore reported for the library, or 0 while unknown.
  int get total => _total;

  bool get isEmpty => _rows.isEmpty;

  /// Bumped whenever rows arrive, for surfaces that cache derived lists.
  int get version => _version;

  void setTotal(int total) {
    if (total <= 0 || total == _total) return;
    _total = total;
    _notify();
  }

  /// Appends rows from the media store stream. Duplicates (a resumed import
  /// re-streams what is already indexed) are ignored, and trashed rows are left
  /// out: this is the library, not the bin.
  void addEntries(Iterable<AvesEntry> entries) {
    var added = 0;
    for (final entry in entries) {
      if (entry.trashed) continue;
      final key = entry.contentId ?? entry.id;
      if (key != 0 && _indexByKey.containsKey(key)) continue;
      final row = BrowseRow.fromEntry(entry);
      final index = _rows.length;
      if (key != 0) _indexByKey[key] = index;
      _rows.add(row);
      final directory = row.directory;
      if (directory != null && directory.isNotEmpty) {
        (_albumRows[directory] ??= []).add(index);
      }
      added++;
    }
    if (added == 0) return;
    _version++;
    _albums = null;
    _months = null;
    _notify();
  }

  BrowseRow rowAt(int index) => _rows[index];

  /// The entry for [index], materialized once and kept in a small LRU, so
  /// scrolling back over painted rows reuses the same instance.
  AvesEntry entryAt(int index) {
    final cached = _entries.remove(index);
    if (cached != null) {
      _entries[index] = cached;
      return cached;
    }
    final row = _rows[index];
    final entry = row.toEntry(id: row.id > 0 ? row.id : index + 1);
    _entries[index] = entry;
    if (_entries.length > _entryCacheMax) {
      _entries.remove(_entries.keys.first);
    }
    return entry;
  }

  /// The position of a row by its media store identity, or -1.
  int indexOfContentId(int contentId) => _indexByKey[contentId] ?? -1;

  /// Visible albums, sorted by display name. Hidden albums are filtered here
  /// rather than at insert time, so a preference change applies to what is
  /// already indexed.
  List<BrowseAlbum> get albums {
    final hidden = _hiddenDirectories();
    final fingerprint = hidden.join('\u0000');
    final cached = _albums;
    if (cached != null && _albumsHidden == fingerprint) return cached;

    final directories = _albumRows.keys.whereNot(hidden.contains).toList();
    // Disambiguate same-named folders, the way the album page does.
    final nameCount = <String, int>{};
    for (final directory in directories) {
      final name = _folderName(directory);
      nameCount[name] = (nameCount[name] ?? 0) + 1;
    }
    final albums = [
      for (final directory in directories)
        BrowseAlbum(
          directory: directory,
          name: nameCount[_folderName(directory)]! > 1 ? _disambiguatedName(directory) : _folderName(directory),
          count: _albumRows[directory]!.length,
          coverIndex: _albumRows[directory]!.first,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _albumsHidden = fingerprint;
    return _albums = albums;
  }

  /// Row positions of one album, newest first.
  List<int> rowsOfAlbum(String directory) => _albumRows[directory] ?? const [];

  /// Row positions of one album in display order.
  List<int> albumIndexes(String directory, {required BrowseMediaSort sort, required bool reverse}) {
    final indexes = _albumRows[directory];
    if (indexes == null || indexes.isEmpty) return const [];
    return _sorted(indexes, sort, reverse);
  }

  /// Row positions in display order, narrowed to videos when asked.
  ///
  /// The videos view is the same index filtered by what MediaStore itself says
  /// the file is: no catalogue, no database, and the switch is instant.
  List<int> mediaIndexes({required BrowseMediaSort sort, required bool reverse, bool videosOnly = false}) {
    final hidden = _hiddenDirectories();
    final key = '${sort.name}|$reverse|$videosOnly|${hidden.join('\u0000')}';
    final cached = _mediaOrder;
    if (cached != null && _mediaOrderKey == key && _mediaOrderVersion == _version) return cached;
    final indexes = <int>[
      for (var index = 0; index < _rows.length; index++)
        if (_isVisible(_rows[index], hidden) && (!videosOnly || _rows[index].isVideo)) index,
    ];
    final ordered = _sorted(indexes, sort, reverse);
    _mediaOrderKey = key;
    _mediaOrderVersion = _version;
    return _mediaOrder = ordered;
  }

  /// Positions of the video rows, in display order.
  List<int> get videoIndexes => mediaIndexes(sort: BrowseMediaSort.date, reverse: false, videosOnly: true);

  /// Visible albums in display order.
  List<BrowseAlbum> albumsSorted({required BrowseAlbumSort sort, required bool reverse}) {
    final hidden = _hiddenDirectories();
    final key = '${sort.name}|$reverse|${hidden.join('\u0000')}';
    final cached = _albumOrder;
    if (cached != null && _albumOrderKey == key && _albumOrderVersion == _version) return cached;
    final dates = _albumMaxDates();
    var albums = List<BrowseAlbum>.of(this.albums);
    switch (sort) {
      case BrowseAlbumSort.date:
        albums.sort((a, b) {
          final c = (dates[b.directory] ?? 0).compareTo(dates[a.directory] ?? 0);
          return c != 0 ? c : _compareAlbumNames(a, b);
        });
      case BrowseAlbumSort.name:
        albums.sort(_compareAlbumNames);
      case BrowseAlbumSort.count:
        albums.sort((a, b) {
          final c = b.count.compareTo(a.count);
          return c != 0 ? c : _compareAlbumNames(a, b);
        });
    }
    if (reverse) albums = albums.reversed.toList(growable: false);
    _albumOrderKey = key;
    _albumOrderVersion = _version;
    return _albumOrder = albums;
  }

  /// Month sections over [indexes], in the order they are given.
  List<BrowseMonth> monthsOf(List<int> indexes) {
    final months = <int, BrowseMonth>{};
    for (final index in indexes) {
      final date = DateTime.fromMillisecondsSinceEpoch(_rows[index].bestDateMillis);
      final key = date.year * 100 + date.month;
      final section = months[key];
      if (section == null) {
        months[key] = BrowseMonth(year: date.year, month: date.month, indexes: [index]);
      } else {
        section.indexes.add(index);
      }
    }
    return months.values.toList(growable: false);
  }

  List<int> _sorted(List<int> indexes, BrowseMediaSort sort, bool reverse) {
    final sorted = List<int>.of(indexes);
    switch (sort) {
      case BrowseMediaSort.date:
        sorted.sort((a, b) {
          final c = _rows[b].bestDateMillis.compareTo(_rows[a].bestDateMillis);
          return c != 0 ? c : b.compareTo(a);
        });
      case BrowseMediaSort.name:
        sorted.sort((a, b) {
          final c = (_rows[a].title ?? '').toLowerCase().compareTo((_rows[b].title ?? '').toLowerCase());
          if (c != 0) return c;
          final d = _rows[b].bestDateMillis.compareTo(_rows[a].bestDateMillis);
          return d != 0 ? d : a.compareTo(b);
        });
    }
    return reverse ? sorted.reversed.toList(growable: false) : sorted;
  }

  Map<String, int> _albumMaxDates() {
    final cached = _albumDates;
    if (cached != null && _albumDatesVersion == _version) return cached;
    final dates = <String, int>{};
    for (var index = 0; index < _rows.length; index++) {
      final directory = _rows[index].directory;
      if (directory == null) continue;
      final date = _rows[index].bestDateMillis;
      final current = dates[directory];
      if (current == null || date > current) dates[directory] = date;
    }
    _albumDatesVersion = _version;
    return _albumDates = dates;
  }

  static int _compareAlbumNames(BrowseAlbum a, BrowseAlbum b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.directory.compareTo(b.directory);
  }

  static bool _isVisible(BrowseRow row, Set<String> hidden) {
    final directory = row.directory;
    return directory == null || !hidden.contains(directory);
  }

  /// The media grid's month sections, newest first.
  ///
  /// Rows in hidden albums are left out, matching what the collection shows.
  List<BrowseMonth> get months {
    final hidden = _hiddenDirectories();
    final fingerprint = hidden.join('\u0000');
    final cached = _months;
    if (cached != null && _monthsHidden == fingerprint) return cached;

    final months = monthsOf(mediaIndexes(sort: BrowseMediaSort.date, reverse: false));
    _monthsHidden = fingerprint;
    return _months = months;
  }

  /// Drops the index, for the handoff back to the collection.
  void clear() {
    _scan = null;
    _scanning = false;
    _scanStopped = false;
    if (_rows.isEmpty) return;
    _rows.clear();
    _indexByKey.clear();
    _albumRows.clear();
    _entries.clear();
    _albums = null;
    _months = null;
    _mediaOrder = null;
    _albumOrder = null;
    _albumDates = null;
    _version++;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Directories the user hid from the collection: the browser hides them too,
  /// instead of surfacing a folder Aves was told not to show.
  static Set<String> _hiddenDirectories() => settings.hiddenFilters.whereType<StoredAlbumFilter>().map((v) => v.album).toSet();

  static String _folderName(String directory) {
    final normalized = directory.endsWith('/') ? directory.substring(0, directory.length - 1) : directory;
    final separator = normalized.lastIndexOf('/');
    return separator < 0 ? normalized : normalized.substring(separator + 1);
  }

  static String _disambiguatedName(String directory) {
    final parts = directory.split('/').where((v) => v.isNotEmpty).toList();
    if (parts.length < 2) return _folderName(directory);
    return '${parts[parts.length - 2]}/${parts.last}';
  }
}

/// The app's single browse index, filled by the import and read by the
/// browse-only surfaces.
final BrowseLibrary browseLibrary = BrowseLibrary();
