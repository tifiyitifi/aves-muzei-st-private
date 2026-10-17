import 'package:aves/ref/bursts.dart';
import 'package:aves/ref/mime_types.dart';
import 'package:aves/services/common/services.dart';
import 'package:collection/collection.dart';

/// One row of a stack group, as the stack policy needs it.
typedef StackRow = ({int id, String? path, String? mimeType});

/// Stack policy: what a stack is, which member is its tile, and which members
/// hide behind it.
///
/// The rules mirror the legacy in-memory stacking (`CollectionLens._stackBursts`
/// followed by `_stackDevelopedRaws`), so a paged view shows the same tiles:
///
/// - a *burst* group is the set of entries sharing a burst key; its tile is the
///   first member by natural name and extension (`AvesEntrySort.compareByName`)
///   and the other members hide;
/// - a *raw* hides when a developed image of the same directory and base name
///   survived the burst pass.
///
/// Unlike the legacy pass, the burst order uses the file name only, never the
/// catalogued `xmpTitle` that `AvesEntry.bestTitle` prefers: a title on one frame
/// of a burst is exotic, and depending on it would move the tile when metadata
/// arrives after the entry itself.
class StackGrouping {
  /// The base name of [path], or null when it has none.
  static String? baseNameOf(String? path) => path == null ? null : pContext.basenameWithoutExtension(path);

  /// The burst group key of an entry, or null when no pattern matches its name.
  static String? stackKeyOf({required String? directory, required String? baseName, required List<String> patterns}) {
    if (directory == null || baseName == null) return null;
    final key = BurstPatterns.getKeyForName(baseName, patterns);
    return key != null ? '$directory/$key' : null;
  }

  /// The order a burst group is shown in (`AvesEntrySort.compareByName`, over
  /// file names): natural, then by extension.
  static int compareNames({required String? pathA, required String? pathB}) => _compareByName((id: -1, path: pathA, mimeType: null), (id: -1, path: pathB, mimeType: null));

  /// The `stackTileId` of every row of one group.
  ///
  /// The tile maps to null, so it needs no test to show; the members map to the
  /// tile's id; a group with no single tile — keyless raws without a developed
  /// image — maps every row to null. [hasBurstKey] tells whether the burst pass
  /// applies: rows without a burst key only take part in the developed-raw pass.
  static Map<int, int?> tileIds(List<StackRow> rows, {required bool hasBurstKey}) {
    final visible = _visibleIds(rows, hasBurstKey: hasBurstKey);
    if (visible.length != 1) {
      return {for (final row in rows) row.id: null};
    }
    final tileId = visible.single;
    return {
      for (final row in rows) row.id: row.id == tileId ? null : tileId,
    };
  }

  /// Ids of the rows of one group that stay visible.
  static Set<int> _visibleIds(List<StackRow> rows, {required bool hasBurstKey}) {
    final burstMainId = hasBurstKey ? _burstMainId(rows) : null;
    bool removedByBurst(StackRow row) => hasBurstKey && row.id != burstMainId;

    // A developed image only pairs with a raw that survived the burst pass.
    final hasSurvivingDeveloped = rows.any((row) => !removedByBurst(row) && _isDeveloped(row.mimeType));
    bool removedByRaw(StackRow row) => hasSurvivingDeveloped && _isRaw(row.mimeType);

    return {
      for (final row in rows)
        if (!removedByBurst(row) && !removedByRaw(row)) row.id,
    };
  }

  /// The group's tile: its first member by natural name and extension.
  static int? _burstMainId(List<StackRow> rows) {
    final sorted = List.of(rows)..sort(_compareByName);
    return sorted.isEmpty ? null : sorted.first.id;
  }

  /// `AvesEntrySort.compareByName`, over the file name instead of `bestTitle`.
  static int _compareByName(StackRow a, StackRow b) {
    final c = compareAsciiUpperCaseNatural(baseNameOf(a.path) ?? '', baseNameOf(b.path) ?? '');
    return c != 0 ? c : compareAsciiUpperCase(_extensionOf(a.path) ?? '', _extensionOf(b.path) ?? '');
  }

  static String? _extensionOf(String? path) => path == null ? null : pContext.extension(path);

  static bool _isDeveloped(String? mimeType) => mimeType != null && MimeTypes.developedRawImages.contains(mimeType);

  static bool _isRaw(String? mimeType) => mimeType != null && MimeTypes.rawImages.contains(mimeType);
}
