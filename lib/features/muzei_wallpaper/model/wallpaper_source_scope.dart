import 'dart:convert';

import 'package:aves/features/muzei_wallpaper/model/wallpaper_source_kind.dart';
import 'package:aves/model/filters/container/album_group.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/mime.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The user's wallpaper source: either a collection scope or one entry.
///
/// The scope is deliberately engine-agnostic. It only stores the serialized
/// [CollectionFilter]s; the source repository translates them to a database
/// predicate when it resolves the next artwork.
///
/// An empty [filters] set on [WallpaperSourceKind.myPhotos] means "all photos"
/// and is a valid scope. [WallpaperSourceKind.single] is only configured once
/// [singleEntryId] is set.
@immutable
class WallpaperSourceScope with Equatable {
  final WallpaperSourceKind kind;
  final Set<CollectionFilter> filters;
  final int? singleEntryId;

  /// Sorted JSON forms, cached because [revision] and persistence both need
  /// them and [filters] is immutable.
  late final List<String> sortedFilterJson = List.unmodifiable(
    filters.map((filter) => filter.toJsonString()).toList()..sort(),
  );

  new({
    this.kind = WallpaperSourceKind.myPhotos,
    Set<CollectionFilter> filters = const {},
    this.singleEntryId,
  }) : filters = Set.unmodifiable(filters);

  bool get isConfigured => kind == WallpaperSourceKind.myPhotos || (singleEntryId ?? 0) > 0;

  /// Collection filters representing a picked album set.
  ///
  /// Aves' collection filters are ANDed, so two album filters in one set match
  /// nothing; several albums are therefore wrapped in a [SetOrFilter] (their
  /// union). The implicit image restriction still applies on top via
  /// [queryFilters].
  static Set<CollectionFilter> filtersForAlbums(Iterable<AlbumBaseFilter> albums) {
    final selected = albums.toSet();
    return switch (selected.length) {
      0 => const <CollectionFilter>{},
      1 => {selected.single},
      _ => {SetOrFilter(selected)},
    };
  }

  /// Filters actually sent to the collection predicate.
  ///
  /// Wallpapers are always still images, so the image MIME restriction is
  /// implicit and cannot be removed by the source editor.
  Set<CollectionFilter> get queryFilters => {
    ...filters,
    MimeFilter.image,
  };

  /// Stable fingerprint of the scope.
  ///
  /// This is not `Object.hashCode`: the value is persisted in `state.json` and
  /// compared after a process restart, so it must only depend on the scope's
  /// content.
  String get revision => '${kind.name}:${_stableHash(jsonEncode(toJsonMap()))}';

  WallpaperSourceScope copyWith({
    WallpaperSourceKind? kind,
    Set<CollectionFilter>? filters,
    int? singleEntryId,
    bool clearSingleEntryId = false,
  }) {
    return WallpaperSourceScope(
      kind: kind ?? this.kind,
      filters: filters ?? this.filters,
      singleEntryId: clearSingleEntryId ? null : (singleEntryId ?? this.singleEntryId),
    );
  }

  Map<String, Object?> toJsonMap() => {
    'kind': kind.name,
    'filters': sortedFilterJson,
    if (singleEntryId != null) 'singleEntryId': singleEntryId,
  };

  String toJsonString() => jsonEncode(toJsonMap());

  static WallpaperSourceScope fromJsonMap(Map<String, Object?> json) {
    final rawKind = json['kind'];
    final kind = WallpaperSourceKind.tryParse(rawKind is String ? rawKind : null) ?? WallpaperSourceKind.myPhotos;
    final filters = <CollectionFilter>{};
    final rawFilters = _decodeFilterList(json['filters']);
    for (final raw in rawFilters) {
      final filter = CollectionFilter.fromJson(raw);
      if (filter != null) filters.add(filter);
    }
    final rawSingleId = json['singleEntryId'];
    final singleId = rawSingleId is int && rawSingleId > 0
        ? rawSingleId
        : rawSingleId is num && rawSingleId > 0
        ? rawSingleId.toInt()
        : null;
    return WallpaperSourceScope(kind: kind, filters: filters, singleEntryId: singleId);
  }

  static WallpaperSourceScope? fromJsonString(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) return fromJsonMap(decoded.map((key, value) => MapEntry(key.toString(), value)));
    } on FormatException {
      // Persisted data may be from an interrupted write; the caller falls back.
    }
    return null;
  }

  static List<Object?> _decodeFilterList(Object? raw) {
    if (raw is List) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      } on FormatException {
        // Ignore malformed legacy value.
      }
    }
    return const [];
  }

  /// 32-bit FNV-1a, stable across runs and platforms.
  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  List<Object?> get props => [kind, sortedFilterJson, singleEntryId];
}
