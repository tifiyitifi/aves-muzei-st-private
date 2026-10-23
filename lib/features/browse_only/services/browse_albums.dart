import 'package:aves/features/browse_only/services/browse_prefs.dart';
import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/media/media_store_service.dart';
import 'package:flutter/foundation.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// A folder as the browser lists it: what the album shows and how much of it.
class BrowseAlbum {
  final String directory;

  /// Display name, disambiguated against same-named folders on other paths.
  final String name;

  /// Rows the media store reports for this folder.
  final int count;

  /// The folder's newest row, as the tile's cover.
  final AvesEntry cover;

  /// The folder's newest date, for the recency order.
  final int maxDateMillis;

  const new({
    required this.directory,
    required this.name,
    required this.count,
    required this.cover,
    required this.maxDateMillis,
  });
}

/// The album list of the browse-only surface.
///
/// It comes from one aggregate read of the media store, not from counting the
/// rows the timeline streams: the list is replaced as a whole, so a count is
/// never seen growing, and a folder is whole even while the timeline is only a
/// preview. The rows a folder holds are read when it is opened, not here.
class BrowseAlbums extends ChangeNotifier {
  /// The raw summaries, so changing the hidden set does not have to re-read
  /// the whole media store.
  List<MediaStoreAlbumSummary> _summaries = const [];
  List<BrowseAlbum>? _visible;
  String _visibleHidden = '';
  bool _loading = false;
  bool _loaded = false;
  Object? _error;
  int _version = 0;

  /// Display orders, keyed by what they were computed from.
  List<BrowseAlbum>? _order;
  String _orderKey = '';
  int _orderVersion = -1;

  bool _disposed = false;

  /// Bumped by `clear`: a read still in flight belongs to the list that was
  /// dropped, not to the one that replaced it.
  int _token = 0;

  /// How long the aggregate read may stay unanswered before reporting it.
  ///
  /// The scan is whole-library, so the bound is generous; its purpose is a lost
  /// platform reply, not a slow read.
  final Duration readTimeout;

  new({this.readTimeout = const Duration(minutes: 3)});

  List<BrowseAlbum> get albums => _visibleAlbums();

  bool get loading => _loading;

  bool get isEmpty => albums.isEmpty;

  Object? get error => _error;

  int get version => _version;

  /// Reads the list. Idempotent, so a surface that mounts again does not re-read
  /// what it already has; a read that failed is retried.
  Future<void> load() {
    if (_disposed || _loading || _loaded) return Future<void>.value();
    return _read();
  }

  Future<void> _read() async {
    final token = _token;
    _loading = true;
    _error = null;
    _notify();
    try {
      final summaries = await mediaStoreService.getAlbumSummaries().timeout(readTimeout);
      if (_disposed || token != _token) return;
      _error = null;
      _loaded = true;
      _summaries = summaries;
      _visible = null;
      _version++;
      _order = null;
    } catch (error, stack) {
      // The album grid shows its empty state: a failed read must not leave the
      // surface claiming to be loading for the rest of the session.
      _log.w('browse-only album summaries failed', error, stack);
      if (_disposed || token != _token) return;
      _error = error;
    } finally {
      if (!_disposed && token == _token) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Visible albums in display order.
  List<BrowseAlbum> albumsSorted({required BrowseAlbumSort sort, required bool reverse}) {
    final current = _visibleAlbums();
    // The hidden set is part of the key: the visible list can change without a
    // new read, and the cached order then describes a different list.
    final key = '${sort.name}|$reverse|$_visibleHidden';
    final cached = _order;
    if (cached != null && _orderKey == key && _orderVersion == _version) return cached;
    var sorted = List<BrowseAlbum>.of(current);
    switch (sort) {
      case BrowseAlbumSort.date:
        sorted.sort((a, b) {
          final c = b.maxDateMillis.compareTo(a.maxDateMillis);
          return c != 0 ? c : _compareAlbumNames(a, b);
        });
      case BrowseAlbumSort.name:
        sorted.sort(_compareAlbumNames);
      case BrowseAlbumSort.count:
        sorted.sort((a, b) {
          final c = b.count.compareTo(a.count);
          return c != 0 ? c : _compareAlbumNames(a, b);
        });
    }
    if (reverse) sorted = sorted.reversed.toList(growable: false);
    _orderKey = key;
    _orderVersion = _version;
    return _order = sorted;
  }

  /// Visible albums, recomputed when the hidden set changes.
  ///
  /// The hidden filters are applied here rather than at read time so a settings
  /// change lands on the list already loaded instead of a full media-store scan.
  List<BrowseAlbum> _visibleAlbums() {
    final hidden = _hiddenDirectories();
    final fingerprint = hidden.join('\u0000');
    final cached = _visible;
    if (cached != null && _visibleHidden == fingerprint) return cached;
    _visibleHidden = fingerprint;
    return _visible = _visibleOf(_summaries);
  }

  /// Turns the summaries into the list the grid shows: hidden folders are left
  /// out, and same-named folders on other paths are disambiguated by their
  /// parent, the way the collection's album page does.
  static List<BrowseAlbum> _visibleOf(List<MediaStoreAlbumSummary> summaries) {
    final hidden = _hiddenDirectories();
    final nameCount = <String, int>{};
    for (final summary in summaries) {
      if (hidden.contains(summary.directory)) continue;
      final name = _folderName(summary.directory);
      nameCount[name] = (nameCount[name] ?? 0) + 1;
    }
    return [
      for (final summary in summaries)
        if (!hidden.contains(summary.directory))
          BrowseAlbum(
            directory: summary.directory,
            name: (nameCount[_folderName(summary.directory)] ?? 0) > 1 ? _disambiguatedName(summary.directory) : _folderName(summary.directory),
            count: summary.count,
            cover: summary.cover,
            maxDateMillis: summary.cover.bestDate?.millisecondsSinceEpoch ?? 0,
          ),
    ];
  }

  static int _compareAlbumNames(BrowseAlbum a, BrowseAlbum b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.directory.compareTo(b.directory);
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

  /// Drops the list, for the handoff back to the collection.
  ///
  /// A read still in flight is released with it: it belongs to the list that
  /// was dropped, and landing it would refill a list nothing will show again.
  void clear() {
    _token++;
    final hadContent = _summaries.isNotEmpty || _error != null || _loaded || _loading;
    _reset();
    if (!hadContent) return;
    _version++;
    _notify();
  }

  void _reset() {
    _summaries = const [];
    _visible = null;
    _visibleHidden = '';
    _order = null;
    _loading = false;
    _loaded = false;
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
}

/// The app's single browse album list, read once and read by the album surfaces.
final BrowseAlbums browseAlbums = BrowseAlbums();
