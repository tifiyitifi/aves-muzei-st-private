import 'package:aves/features/search_filters/model/range_assist_filter.dart';
import 'package:aves/features/search_filters/model/relative_time_filter.dart';
import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:aves/locale/aves_locale.dart';
import 'package:aves/model/filters/container/set_or.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/path.dart';
import 'package:aves/model/filters/query.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// One removable condition of the search assist.
enum AssistField { path, takenDate, size, dimension, contentId, recent, extension }

/// Whether a path condition keeps only that directory or hides it.
enum PathAssistMode {
  include,
  exclude;

  static PathAssistMode parse(String? value) => value == exclude.name ? exclude : include;
}

/// A directory condition: the entries under [path], or everything but them.
@immutable
class PathAssist extends Equatable {
  final String path;
  final PathAssistMode mode;

  const new({required this.path, this.mode = PathAssistMode.include});

  CollectionFilter toFilter() => PathFilter(path, reversed: mode == PathAssistMode.exclude);

  @override
  List<Object?> get props => [path, mode];
}

/// An inclusive numeric range; a null bound is open.
@immutable
class AssistIntRange extends Equatable {
  final int? min;
  final int? max;

  const new({this.min, this.max});

  bool get isEmpty => min == null && max == null;

  RangeAssistFilter? toFilter(AssistRangeField field) => isEmpty ? null : RangeAssistFilter(field, min: min, max: max);

  @override
  List<Object?> get props => [min, max];
}

/// Width and height ranges of the displayed size (rotation included).
@immutable
class AssistDimension extends Equatable {
  final AssistIntRange width;
  final AssistIntRange height;

  const new({this.width = const AssistIntRange(), this.height = const AssistIntRange()});

  bool get isEmpty => width.isEmpty && height.isEmpty;

  @override
  List<Object?> get props => [width, height];
}

/// "The last N hours/days" condition.
@immutable
class AssistRecent extends Equatable {
  final int amount;
  final RelativeTimeUnit unit;

  const new({required this.amount, required this.unit});

  RelativeTimeFilter toFilter() => RelativeTimeFilter(TimeToNow(amount: amount, unit: unit));

  @override
  List<Object?> get props => [amount, unit];
}

/// The whole assist state: the conditions the user added on the search page.
///
/// It is a plain value so the sheets can hand a new copy back, a chip can drop
/// one field, and the delegate only has to turn it into filters once.
@immutable
class SearchAssist extends Equatable {
  final PathAssist? path;
  final AssistIntRange? takenDate;
  final AssistIntRange? size;
  final AssistDimension? dimension;
  final AssistIntRange? contentId;
  final AssistRecent? recent;

  /// Lowercase extensions without the dot, OR-ed together.
  final Set<String> extensions;

  const new({
    this.path,
    this.takenDate,
    this.size,
    this.dimension,
    this.contentId,
    this.recent,
    this.extensions = const {},
  });

  static const empty = SearchAssist();

  bool get isEmpty =>
      path == null && takenDate == null && size == null && (dimension?.isEmpty ?? true) && contentId == null && recent == null && extensions.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Whether the "other" sheet holds anything (everything except the path).
  bool get hasOther => takenDate != null || size != null || !(dimension?.isEmpty ?? true) || contentId != null || recent != null || extensions.isNotEmpty;

  /// The filters this state stands for, AND-ed by the collection.
  ///
  /// [calendar] only reaches the extension conditions: they are expressed with
  /// the app's own `EXT` query so the existing query compiler (and its tests)
  /// keep owning extension matching.
  Set<CollectionFilter> toFilters({ACalendar calendar = ACalendar.gregorian}) {
    final result = <CollectionFilter>{};

    final path = this.path;
    if (path != null) result.add(path.toFilter());

    final takenDate = this.takenDate;
    final dateFilter = takenDate?.toFilter(AssistRangeField.takenDate);
    if (dateFilter != null) result.add(dateFilter);

    final size = this.size;
    final sizeFilter = size?.toFilter(AssistRangeField.size);
    if (sizeFilter != null) result.add(sizeFilter);

    final dimension = this.dimension;
    if (dimension != null) {
      final width = dimension.width.toFilter(AssistRangeField.width);
      if (width != null) result.add(width);
      final height = dimension.height.toFilter(AssistRangeField.height);
      if (height != null) result.add(height);
    }

    final contentId = this.contentId;
    final idFilter = contentId?.toFilter(AssistRangeField.contentId);
    if (idFilter != null) result.add(idFilter);

    final recent = this.recent;
    if (recent != null) result.add(recent.toFilter());

    if (extensions.isNotEmpty) {
      final byExtension = {
        for (final extension in extensions) QueryFilter('${QueryFilter.keyContentExtension}=$extension', calendar),
      };
      result.add(byExtension.length == 1 ? byExtension.first : SetOrFilter(byExtension));
    }

    return result;
  }

  SearchAssist withPath(PathAssist? value) => SearchAssist(
        path: value,
        takenDate: takenDate,
        size: size,
        dimension: dimension,
        contentId: contentId,
        recent: recent,
        extensions: extensions,
      );

  SearchAssist withTakenDate(AssistIntRange? value) => SearchAssist(
        path: path,
        takenDate: value,
        size: size,
        dimension: dimension,
        contentId: contentId,
        recent: recent,
        extensions: extensions,
      );

  SearchAssist withSize(AssistIntRange? value) => SearchAssist(
        path: path,
        takenDate: takenDate,
        size: value,
        dimension: dimension,
        contentId: contentId,
        recent: recent,
        extensions: extensions,
      );

  SearchAssist withDimension(AssistDimension? value) => SearchAssist(
        path: path,
        takenDate: takenDate,
        size: size,
        dimension: value,
        contentId: contentId,
        recent: recent,
        extensions: extensions,
      );

  SearchAssist withContentId(AssistIntRange? value) => SearchAssist(
        path: path,
        takenDate: takenDate,
        size: size,
        dimension: dimension,
        contentId: value,
        recent: recent,
        extensions: extensions,
      );

  SearchAssist withRecent(AssistRecent? value) => SearchAssist(
        path: path,
        takenDate: takenDate,
        size: size,
        dimension: dimension,
        contentId: contentId,
        recent: value,
        extensions: extensions,
      );

  SearchAssist withExtensions(Set<String> value) => SearchAssist(
        path: path,
        takenDate: takenDate,
        size: size,
        dimension: dimension,
        contentId: contentId,
        recent: recent,
        extensions: {for (final extension in value) extension.toLowerCase().replaceFirst('.', '')},
      );

  /// Drops everything the "other" sheet owns, keeping the path condition.
  SearchAssist clearOther() => SearchAssist(path: path);

  SearchAssist without(AssistField field) => switch (field) {
        AssistField.path => withPath(null),
        AssistField.takenDate => withTakenDate(null),
        AssistField.size => withSize(null),
        AssistField.dimension => withDimension(null),
        AssistField.contentId => withContentId(null),
        AssistField.recent => withRecent(null),
        AssistField.extension => withExtensions(const {}),
      };

  @override
  List<Object?> get props => [path, takenDate, size, dimension, contentId, recent, extensions];
}
