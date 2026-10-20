import 'dart:async';

import 'package:aves/features/collection_paging/engine/collection_paging_prefs.dart';
import 'package:aves/features/logging/log.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = AreaKeyLog(collectionPagingLogKey);

/// How the browse-only timeline orders its rows.
enum BrowseMediaSort { date, name }

/// How the browse-only album grid orders its folders.
enum BrowseAlbumSort { date, name, count }

/// Sort preferences owned by the browse-only surface.
///
/// They live in their own namespace on purpose: the browser is a temporary
/// surface with its own navigation, and letting it write the collection's sort
/// settings would silently reshape the app the user gets back once the import
/// finishes. Same for reading: the browser starts from what a gallery normally
/// shows (newest first, albums by recency), not from a preference the user tuned
/// for Aves's own albums page.
class BrowsePrefs extends ChangeNotifier {
  static const _mediaSortKey = 'browse_only.media_sort';
  static const _mediaReverseKey = 'browse_only.media_reverse';
  static const _albumSortKey = 'browse_only.album_sort';
  static const _albumReverseKey = 'browse_only.album_reverse';

  BrowseMediaSort _mediaSort = BrowseMediaSort.date;

  /// `false` means "newest first" for date and "A to Z" for name.
  bool _mediaReverse = false;

  BrowseAlbumSort _albumSort = BrowseAlbumSort.date;

  /// `false` means "newest first" for date, "A to Z" for name, "most items"
  /// for count.
  bool _albumReverse = false;

  bool _loaded = false;

  Future<void>? _init;

  BrowseMediaSort get mediaSort => _mediaSort;

  bool get mediaReverse => _mediaReverse;

  BrowseAlbumSort get albumSort => _albumSort;

  bool get albumReverse => _albumReverse;

  bool get isLoaded => _loaded;

  Future<void> init() => _init ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mediaSort = BrowseMediaSort.values.asNameMap()[prefs.getString(_mediaSortKey)] ?? _mediaSort;
      _mediaReverse = prefs.getBool(_mediaReverseKey) ?? _mediaReverse;
      _albumSort = BrowseAlbumSort.values.asNameMap()[prefs.getString(_albumSortKey)] ?? _albumSort;
      _albumReverse = prefs.getBool(_albumReverseKey) ?? _albumReverse;
    } catch (error) {
      // Defaults are a valid sort; a failed read must not block the browser.
      _log.w('browse-only prefs read failed', error);
    }
    _loaded = true;
    notifyListeners();
  }

  void setMediaSort(BrowseMediaSort sort, bool reverse) {
    if (sort == _mediaSort && reverse == _mediaReverse) return;
    _mediaSort = sort;
    _mediaReverse = reverse;
    notifyListeners();
    unawaited(_persist((prefs) async {
      await prefs.setString(_mediaSortKey, sort.name);
      await prefs.setBool(_mediaReverseKey, reverse);
    }));
  }

  void setAlbumSort(BrowseAlbumSort sort, bool reverse) {
    if (sort == _albumSort && reverse == _albumReverse) return;
    _albumSort = sort;
    _albumReverse = reverse;
    notifyListeners();
    unawaited(_persist((prefs) async {
      await prefs.setString(_albumSortKey, sort.name);
      await prefs.setBool(_albumReverseKey, reverse);
    }));
  }

  Future<void> _persist(Future<void> Function(SharedPreferences prefs) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (error) {
      _log.w('browse-only prefs write failed', error);
    }
  }
}

/// The app's single browse-only preference set.
final BrowsePrefs browsePrefs = BrowsePrefs();
