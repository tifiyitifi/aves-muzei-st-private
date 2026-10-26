import 'package:aves/features/search_filters/model/time_to_now.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

/// Entries whose best date falls inside the last [span] before [cutoffMillis].
///
/// The window is anchored once, when the filter is built, and the SQL fragment
/// reads the very same instant: an in-memory browse and a database window can
/// never disagree about where the window starts. A filter restored from search
/// history is rebuilt, so it re-anchors to the moment it is used again.
class RelativeTimeFilter extends CollectionFilter {
  static const type = 'relative_time';

  final TimeToNow span;

  /// Start of the window, in epoch milliseconds.
  final int cutoffMillis;

  late final EntryPredicate _test;

  @override
  List<Object?> get props => [span, reversed];

  new(this.span, {DateTime? now, super.reversed = false}) : cutoffMillis = (now ?? DateTime.now()).millisecondsSinceEpoch - span.millis {
    _test = (entry) {
      final date = entry.bestDate;
      return date != null && date.millisecondsSinceEpoch >= cutoffMillis;
    };
  }

  factory fromMap(Map<String, Object?> json) {
    final span = TimeToNow.parse(json['span'] as String?);
    if (span == null) throw const FormatException('invalid relative time span');
    return RelativeTimeFilter(span, reversed: json['reversed'] as bool? ?? false);
  }

  @override
  Map<String, Object?> toJsonMap() => {
        'type': type,
        'span': span.token,
        if (reversed) 'reversed': reversed,
      };

  @override
  EntryPredicate get positiveTest => _test;

  @override
  bool get exclusiveProp => false;

  @override
  String get universalLabel => span.token;

  @override
  String getLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (span.unit) {
      RelativeTimeUnit.hour => l10n.searchAssistRecentHours(span.amount),
      RelativeTimeUnit.day => l10n.searchAssistRecentDays(span.amount),
    };
  }

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) =>
      Icon(AIcons.searchAssistTime, size: size);

  @override
  String get category => type;

  @override
  String get key => '$type-$reversed-${span.token}';
}
