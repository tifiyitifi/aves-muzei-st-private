import 'dart:collection';

import 'package:aves/features/collection_paging/lens/skeleton_entry.dart';
import 'package:aves/features/collection_paging/windows/window_cache.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/selection.dart';
import 'package:aves/model/source/section_keys.dart';

/// A section's rows as a fixed-length lazy list: positions always resolve
/// (loaded rows or the section skeleton), fetches never block.
///
/// `length` is the section count from the headers, so sliver geometry is exact
/// before any row arrives. `contains`/`indexOf` consult the loaded-index map
/// instead of scanning, so highlight tracking stays O(1) on huge sections.
///
/// Deliberate asymmetry, documented for the callers that depend on each side:
/// - `contains` answers membership in the *collection*: any real entry counts
///   as contained, even while its row is evicted. This keeps
///   `_sanitizeSelection` from dropping still-valid selections.
/// - `indexOf` answers a *position*: only loaded rows (and this section's
///   skeleton, at the section start) resolve; everything else is -1.
class PagedSectionList extends ListBase<AvesEntry> implements SelectionLazySource<AvesEntry> {
  final SectionKey sectionKey;

  final int count;
  /// Local index -> loaded entry. Mirrors exactly what the cache holds:
  /// fills and evictions sync through the cache callbacks.
  final Map<int, AvesEntry> loaded = {};

  /// Entry id -> local index, for O(1) position lookups.
  final Map<int, int> idToLocal = {};

  final SkeletonEntry skeleton;

  /// Fetching store behind this list. Set by the lens after construction;
  /// misses kick off coalesced fetches through it.
  WindowCache<AvesEntry>? cache;

  new({
    required this.sectionKey,
    required this.count,
    required this.skeleton,
  });

  @override
  int get length => count;

  @override
  set length(int value) {
    if (value != count) throw UnsupportedError('paged section lists have a fixed length');
  }

  @override
  AvesEntry operator [](int index) {
    RangeError.checkValidRange(index, null, count);
    final cached = loaded[index];
    if (cached != null) return cached;
    // Miss: kick off a coalesced fetch and render the skeleton meanwhile.
    // Reads never block; the fill notifies through the cache callbacks.
    cache?.ensure(index);
    return skeleton;
  }

  /// The section's real rows, ascending. Read by selection queries, which must
  /// not walk the positions (see [SelectionLazySource]).
  @override
  Iterable<AvesEntry> get loadedItems {
    final keys = loaded.keys.toList()..sort();
    return [for (final key in keys) loaded[key]!];
  }

  @override
  void operator []=(int index, AvesEntry value) => throw UnsupportedError('paged section lists are read-only');

  @override
  bool contains(Object? element) {
    // Precise: only loaded rows belong to this section. The flat list is the
    // lenient one (see [PagedFlatList]); section geometry must resolve to the
    // single owning section for `getTileRect` to stay correct.
    if (element is SkeletonEntry) return element.sectionKey == sectionKey;
    if (element is AvesEntry) return idToLocal.containsKey(element.id);
    return false;
  }

  @override
  int indexOf(Object? element, [int start = 0]) {
    if (element is SkeletonEntry) return element.sectionKey == sectionKey && start <= 0 ? 0 : -1;
    if (element is AvesEntry) {
      final local = idToLocal[element.id];
      return (local != null && local >= start) ? local : -1;
    }
    return -1;
  }
}

/// The whole collection as one fixed-length lazy list over section lists.
///
/// Global index -> section via prefix sums (binary search), so random access
/// stays logarithmic in the section count while sections stay independently
/// windowed. Same contains/indexOf contract as [PagedSectionList].
class PagedFlatList extends ListBase<AvesEntry> implements SelectionLazySource<AvesEntry> {
  final List<PagedSectionList> sections;

  /// Global start index per section, ascending.
  final List<int> _starts;

  /// Entry id -> global index, for O(1) position lookups.
  final Map<int, int> idToGlobal = {};

  new(this.sections) : _starts = _computeStarts(sections);

  static List<int> _computeStarts(List<PagedSectionList> sections) {
    final starts = <int>[];
    var next = 0;
    for (final section in sections) {
      starts.add(next);
      next += section.count;
    }
    return starts;
  }

  int get total => _starts.isEmpty ? 0 : _starts.last + sections.last.count;

  (PagedSectionList, int) locate(int globalIndex) {
    RangeError.checkValidRange(globalIndex, null, total);
    var lo = 0, hi = sections.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= globalIndex) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (sections[lo], globalIndex - _starts[lo]);
  }

  int sectionStart(AvesEntry element) {
    if (element is! SkeletonEntry) return -1;
    final index = sections.indexWhere((s) => s.sectionKey == element.sectionKey);
    return index < 0 ? -1 : _starts[index];
  }

  @override
  int get length => total;

  @override
  set length(int value) {
    if (value != total) throw UnsupportedError('paged flat lists have a fixed length');
  }

  @override
  AvesEntry operator [](int index) {
    final (section, local) = locate(index);
    return section[local];
  }

  /// Every loaded row of the collection, in global index order. Read by
  /// selection queries, which must not walk the positions.
  @override
  Iterable<AvesEntry> get loadedItems => [for (final section in sections) ...section.loadedItems];

  @override
  void operator []=(int index, AvesEntry value) => throw UnsupportedError('paged flat lists are read-only');

  @override
  bool contains(Object? element) {
    // Lenient by design: any real entry counts as contained, even while its
    // row is evicted from the windows. This keeps `_sanitizeSelection` from
    // dropping still-valid selections on every window rotation. Position
    // queries ([indexOf], [locate]) stay strict.
    if (element is SkeletonEntry) return sections.any((s) => s.sectionKey == element.sectionKey);
    if (element is AvesEntry) return true;
    return false;
  }

  @override
  int indexOf(Object? element, [int start = 0]) {
    if (element is SkeletonEntry) {
      final global = sectionStart(element);
      return global >= start ? global : -1;
    }
    if (element is AvesEntry) {
      final global = idToGlobal[element.id];
      return (global != null && global >= start) ? global : -1;
    }
    return -1;
  }
}
