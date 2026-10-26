import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/utils/file_utils.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// The numeric dimensions a [RangeAssistFilter] can constrain.
///
/// They all reduce to "a value of the entry lies between two bounds", which is
/// what lets one filter cover dates, sizes, dimensions and content ids instead
/// of four nearly identical classes.
enum AssistRangeField {
  takenDate,
  size,
  width,
  height,
  contentId;

  static AssistRangeField? parse(String? value) {
    for (final field in AssistRangeField.values) {
      if (field.name == value) return field;
    }
    return null;
  }
}

/// An inclusive numeric range over one [AssistRangeField].
///
/// A null bound is open on that side, so `min` alone reads "at least" and `max`
/// alone reads "at most". The filter always carries at least one bound; an
/// unbounded range would match everything and is never built (the assist drops
/// the condition instead).
class RangeAssistFilter extends CollectionFilter {
  static const type = 'assist_range';

  final AssistRangeField field;
  final int? min;
  final int? max;

  late final EntryPredicate _test;

  @override
  List<Object?> get props => [field, min, max, reversed];

  new(this.field, {this.min, this.max, super.reversed = false}) {
    final min = this.min;
    final max = this.max;
    _test = (entry) {
      final value = _valueOf(entry);
      if (value == null) return false;
      if (min != null && value < min) return false;
      if (max != null && value > max) return false;
      return true;
    };
  }

  factory fromMap(Map<String, Object?> json) {
    final field = AssistRangeField.parse(json['field'] as String?);
    if (field == null) throw const FormatException('invalid assist range field');
    return RangeAssistFilter(
      field,
      min: json['min'] as int?,
      max: json['max'] as int?,
      reversed: json['reversed'] as bool? ?? false,
    );
  }

  @override
  Map<String, Object?> toJsonMap() => {
        'type': type,
        'field': field.name,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (reversed) 'reversed': reversed,
      };

  /// The entry's value for [field], or null when it has none.
  ///
  /// Missing values never match a range: an entry with no date is not "before
  /// 2020", it simply has no date to compare.
  int? _valueOf(AvesEntry entry) => switch (field) {
        AssistRangeField.takenDate => entry.bestDate?.millisecondsSinceEpoch,
        AssistRangeField.size => entry.sizeBytes ?? 0,
        AssistRangeField.width => entry.displaySize.width.round(),
        AssistRangeField.height => entry.displaySize.height.round(),
        AssistRangeField.contentId => entry.contentId,
      };

  @override
  EntryPredicate get positiveTest => _test;

  @override
  bool get exclusiveProp => false;

  @override
  String get universalLabel => '${field.name} ${min ?? ''}-${max ?? ''}';

  @override
  String getLabel(BuildContext context) {
    final l10n = context.l10n;
    final fieldLabel = switch (field) {
      AssistRangeField.takenDate => l10n.searchAssistFieldTakenDate,
      AssistRangeField.size => l10n.searchAssistFieldSize,
      AssistRangeField.width => l10n.searchAssistFieldWidth,
      AssistRangeField.height => l10n.searchAssistFieldHeight,
      AssistRangeField.contentId => l10n.searchAssistFieldId,
    };
    return l10n.searchAssistRangeLabel(fieldLabel, _formatRange(context));
  }

  String _formatRange(BuildContext context) {
    final min = this.min;
    final max = this.max;
    final l10n = context.l10n;
    if (min != null && max != null) {
      return l10n.searchAssistRangeBetween(_formatValue(context, min), _formatValue(context, max));
    }
    if (min != null) return l10n.searchAssistRangeAtLeast(_formatValue(context, min));
    if (max != null) return l10n.searchAssistRangeAtMost(_formatValue(context, max));
    return '';
  }

  String _formatValue(BuildContext context, int value) {
    switch (field) {
      case AssistRangeField.takenDate:
        return MaterialLocalizations.of(context).formatShortDate(DateTime.fromMillisecondsSinceEpoch(value));
      case AssistRangeField.size:
        return formatFileSize(settings.avesLocale, value);
      default:
        return '$value';
    }
  }

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) => Icon(
        switch (field) {
          AssistRangeField.takenDate => AIcons.date,
          AssistRangeField.size => AIcons.size,
          AssistRangeField.width || AssistRangeField.height => AIcons.thumbnailLarge,
          AssistRangeField.contentId => AIcons.tag,
        },
        size: size,
      );

  @override
  String get category => type;

  @override
  String get key => '$type-$reversed-${field.name}-${min ?? ''}-${max ?? ''}';
}
