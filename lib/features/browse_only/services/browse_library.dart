import 'dart:collection';

import 'package:aves/features/browse_only/model/browse_row.dart';
import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

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

/// A window of the library as browsing needs it: rows read in pages, plus the
/// order and sections the grid renders.
///
/// The rows come from the media store a page at a time (`getMediaPage`), not
/// from a walk over the whole library: a first screen costs one bounded query,
/// and deeper scrolling costs one more per screen. Nothing here touches the
/// database or `CollectionSource`, so a half-built import cannot make a folder
/// look empty and a surface can never read a half-written aggregate.
///
/// The whole-library timeline is a *preview*: it stops at [previewRowLimit]
/// rows (the album list is whole, and the collection takes over with the full
/// timeline when the import ends). An album's contents are the same window with
/// no limit and a [directory].
class BrowseLibrary extends ChangeNotifier {
  /// Rows a page read returns. One native query, one reply: the first page is
  /// what the first frame paints.
  static const int pageSize = 250;

  /// Rows the browse-only timeline keeps before it stops loading on its own.
  ///
  /// A compact row is a few hundred bytes, so this is a few MB: enough to browse
  /// through a long import, bounded so the preview can never grow into the
  /// library the collection exists to hold. Past it the user can ask for more.
  static const int previewRowLimit = 5000;

  /// Materialized entries kept around for the visible rows. Small on purpose:
  /// the compact rows are the index, entries are a rendering detail.
  static const int _entryCacheMax = 600;

  /// The folder this window is scoped to, or null for the whole library.
  final String? directory;

  /// Rows the window keeps before it stops loading on its own, or null for a
  /// window that reads its folder whole.
  final int? rowLimit;

  final List<BrowseRow> _rows = [];

  /// Row identity to position, so a page that overlaps what is already indexed
  /// cannot duplicate it.
  final Map<int, int> _indexByKey = {};

  final LinkedHashMap<int, AvesEntry> _entries = LinkedHashMap();

  int _version = 0;
  List<BrowseMonth>? _months;

  /// Display orders, keyed by what they were computed from. A sort change or a
  /// new page invalidates them; the index itself never moves.
  List<int>? _mediaOrder;
  String _mediaOrderKey = '';
  int _mediaOrderVersion = -1;

  /// The hidden-album set the month cache was built with: a preferences change
  /// has to show immediately, and the index itself does not change.
  String _monthsHidden = '';

  bool _disposed = false;
  bool _loading = false;
  bool _started = false;
  bool _hasMore = true;
  bool _limitRaised = false;
  Object? _error;

  /// Bumped by `clear`: a page still in flight belongs to the window that was
  /// dropped, not to the one that replaced it.
  int _token = 0;

  new({this.directory, this.rowLimit});

  /// Rows read so far.
  int get length => _rows.length;

  bool get isEmpty => _rows.isEmpty;

  /// Whether a page read is in flight.
  bool get loading => _loading;

  /// Whether more rows can still be read.
  bool get hasMore => _hasMore && !atLimit;

  /// Whether the window stopped at its own limit rather than at the end of the
  /// library.
  bool get atLimit => rowLimit != null && !_limitRaised && _rows.length >= rowLimit!;

  /// The last page failed. The rows already read are still shown: a read that
  /// broke is not the end of the library.
  Object? get error => _error;

  /// Bumped whenever rows arrive, for surfaces that cache derived lists.
  int get version => _version;

  /// Reads the first page. Idempotent: a surface that mounts again does not
  /// re-read what it already has.
  Future<void> loadFirstPage() {
    if (_started || _disposed) return Future<void>.value();
    _started = true;
    return _loadPage();
  }

  /// Reads the page after the rows already read.
  ///
  /// [beyondPreviewLimit] is the user asking for more than the preview keeps:
  /// the window keeps loading for as long as they do.
  Future<void> loadMore({bool beyondPreviewLimit = false}) {
    if (_disposed || _loading || !_hasMore) return Future<void>.value();
    if (atLimit) {
      if (!beyondPreviewLimit) return Future<void>.value();
      _limitRaised = true;
    }
    return _loadPage();
  }

  /// Reads the whole window, a page at a time. Used by an album's contents,
  /// whose folder is shown whole the way its count already is.
  Future<void> loadAll() async {
    await loadFirstPage();
    while (hasMore) {
      await loadMore();
    }
  }

  /// Retries the page that failed. The rows already read stay on screen: a read
  /// that broke is not the end of the library.
  Future<void> retry() {
    if (_disposed || _loading || _error == null) return Future<void>.value();
    _error = null;
    _hasMore = true;
    return _loadPage();
  }

  Future<void> _loadPage() async {
    if (_disposed || _loading) return;
    _loading = true;
    final token = _token;
    _notify();
    try {
      final cursor = _rows.isEmpty ? null : _cursorOf(_rows.last);
      if (_rows.isNotEmpty && cursor == null) {
        // Without an identity there is nothing to resume from, and asking for
        // the first page again would loop: stopping is the only safe answer.
        _log.w('browse-only page cannot resume: the last row has no content id');
        _hasMore = false;
        return;
      }
      final page = await mediaStoreService.getMediaPage(
        limit: pageSize,
        beforeSortDateSecs: cursor?.$1,
        beforeId: cursor?.$2,
        directory: directory,
      );
      if (_disposed || token != _token) return;
      _error = null;
      addEntries(page.entries);
      _hasMore = page.hasMore;
    } catch (error, stack) {
      if (_disposed || token != _token) return;
      _log.w('browse-only page failed for directory=$directory', error, stack);
      _error = error;
      _hasMore = false;
    } finally {
      if (!_disposed && token == _token) {
        _loading = false;
        _notify();
      }
    }
  }

  /// The keyset a page resumes from: the row's sort date and its media store id,
  /// exactly as the platform orders them.
  static (int, int)? _cursorOf(BrowseRow row) {
    final id = row.contentId;
    if (id == null || id <= 0) return null;
    return (row.bestDateMillis ~/ 1000, id);
  }

  /// Appends rows from a page. Duplicates are ignored and trashed rows are left
  /// out: this is the library, not the bin.
  void addEntries(Iterable<AvesEntry> entries) {
    var added = 0;
    for (final entry in entries) {
      if (entry.trashed) continue;
      final contentId = entry.contentId;
      final usableContentId = contentId != null && contentId > 0 ? contentId : null;
      if (usableContentId != null && _indexByKey.containsKey(usableContentId)) continue;
      final row = BrowseRow.fromEntry(entry);
      final index = _rows.length;
      if (usableContentId != null) _indexByKey[usableContentId] = index;
      _rows.add(row);
      added++;
    }
    if (added == 0) return;
    _version++;
    _months = null;
    _mediaOrder = null;
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
    // Browse rows have no database id: the media store stream does not hand one
    // out, and this index is not the database. The synthetic id lives in the
    // negative domain so it can never equal a real row id and alias another
    // entry in a viewer or selection keyed by id.
    final entry = row.toEntry(id: -(index + 1));
    _entries[index] = entry;
    if (_entries.length > _entryCacheMax) {
      _entries.remove(_entries.keys.first);
    }
    return entry;
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

  /// Drops the window, for the handoff back to the collection.
  ///
  /// A page still in flight is released with it: it belongs to the window that
  /// was dropped, and landing it would refill a library nothing will show again.
  void clear() {
    _token++;
    final hadContent = _rows.isNotEmpty || _error != null || !_hasMore;
    _reset();
    if (!hadContent) return;
    _version++;
    _notify();
  }

  void _reset() {
    _rows.clear();
    _indexByKey.clear();
    _entries.clear();
    _months = null;
    _mediaOrder = null;
    _hasMore = true;
    _loading = false;
    _started = false;
    _limitRaised = false;
    _error = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Directories the user hid from the collection: the browser hides them too,
  /// instead of surfacing a folder Aves was told not to show.
  static Set<String> _hiddenDirectories() => settings.hiddenFilters.whereType<StoredAlbumFilter>().map((v) => v.album).toSet();
}

/// The app's browse-only timeline window, filled a page at a time and read by
/// the browse-only surfaces.
final BrowseLibrary browseLibrary = BrowseLibrary(rowLimit: BrowseLibrary.previewRowLimit);
