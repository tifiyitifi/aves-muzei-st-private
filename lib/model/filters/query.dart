import 'package:aves/locale/aves_locale.dart';
import 'package:aves/locale/calendar/calendar_utils.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/theme/colors.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/utils/file_utils.dart';
import 'package:aves_utils/aves_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class QueryFilter extends CollectionFilter {
  static const type = 'query';

  static final _exactRegex = RegExp('^"(.*)"\$');
  static final _regexRegex = RegExp('^/(.*)/\$');

  final String query;
  final ACalendar calendar;
  final bool colorful, live;

  /// The `KEY<op>value` form of this query, resolved once.
  ///
  /// Null when the query resolved to a regular expression or a plain title
  /// search. Exposed so the database compiler translates a field query without
  /// parsing the string a second time.
  late final QueryField? field = _parseField(query.toUpperCase());

  late final EntryPredicate _test = _resolveTest();

  @override
  List<Object?> get props => [query, calendar, live, reversed];

  static final _fieldPattern = RegExp(r'(.+)([=<>])(.+)');
  static final _fileSizePattern = RegExp(r'(\d+)([KMG])?');
  static const keyContentExtension = 'EXT';
  static const keyContentId = 'ID';
  static const keyContentYear = 'YEAR';
  static const keyContentMonth = 'MONTH';
  static const keyContentDay = 'DAY';
  static const keyContentWidth = 'WIDTH';
  static const keyContentHeight = 'HEIGHT';
  static const keyContentSize = 'SIZE';
  static const opEqual = '=';
  static const opLower = '<';
  static const opGreater = '>';

  new(this.query, this.calendar, {this.colorful = true, this.live = false, super.reversed = false});

  factory fromMap(Map<String, Object?> json) {
    return QueryFilter(
      json['query'] as String,
      ACalendar.values.safeByName(json['calendar'] as String?) ?? .gregorian,
      reversed: json['reversed'] as bool? ?? false,
    );
  }

  @override
  Map<String, Object?> toJsonMap() => {
    'type': type,
    'query': query,
    if (calendar != .gregorian) 'calendar': calendar.name,
    if (reversed) 'reversed': reversed,
  };

  @override
  EntryPredicate get positiveTest => _test;

  @override
  bool get exclusiveProp => false;

  @override
  String get universalLabel => query;

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) => Icon(AIcons.text, fill: 1, size: size);

  @override
  Future<Color> color(BuildContext context) {
    if (colorful) {
      return super.color(context);
    }

    final colors = context.read<AvesColorsData>();
    return SynchronousFuture(colors.neutral);
  }

  @override
  String get category => type;

  @override
  String get key => '$type-$reversed-${calendar.name}-$query';

  /// Resolves the query string once, in the legacy order: `/regex/`, then a
  /// `KEY<op>value` field query, then the default title search.
  EntryPredicate _resolveTest() {
    // allow regex queries wrapped with `/.../`
    final regexMatches = _regexRegex.allMatches(query);
    if (regexMatches.length == 1) {
      try {
        final regex = RegExp(regexMatches.first.group(1)!);
        return (entry) {
          final title = entry.bestTitle;
          return title != null && regex.hasMatch(title);
        };
      } on FormatException catch (_) {
        // invalid regex
        return (entry) => false;
      }
    }

    final field = this.field;
    if (field != null) {
      final test = _testForField(field);
      if (test != null) return test;
    }

    var upQuery = query.toUpperCase();

    // allow NOT queries starting with `-`
    final not = upQuery.startsWith('-');
    if (not) {
      upQuery = upQuery.substring(1);
    }

    // allow untrimmed queries wrapped with `"..."`
    final exactMatches = _exactRegex.allMatches(upQuery);
    if (exactMatches.length == 1) {
      upQuery = exactMatches.first.group(1)!;
    }

    // default to title search
    bool testTitle(AvesEntry entry) => entry.bestTitle?.toUpperCase().contains(upQuery) == true;
    return not ? (entry) => !testTitle(entry) : testTitle;
  }

  /// The in-memory test of a parsed field query, or null when the key has none
  /// for the operation (which sends the query to the title search).
  EntryPredicate? _testForField(QueryField field) {
    switch (field.key) {
      case keyContentExtension:
        final extension = field.text;
        if (extension == null) return null;
        return (entry) => entry.extension?.toUpperCase() == extension;
      case keyContentId:
        final contentId = field.value;
        return (entry) => entry.contentId == contentId;
      case keyContentYear:
        return _numericTest(field.op, (entry) => _datePart(entry, 0), field.value);
      case keyContentMonth:
        return _numericTest(field.op, (entry) => _datePart(entry, 1), field.value);
      case keyContentDay:
        return _numericTest(field.op, (entry) => _datePart(entry, 2), field.value);
      case keyContentWidth:
        return _numericTest(field.op, (entry) => entry.displaySize.width, field.value);
      case keyContentHeight:
        return _numericTest(field.op, (entry) => entry.displaySize.height, field.value);
      case keyContentSize:
        return _numericTest(field.op, (entry) => entry.sizeBytes ?? 0, field.value);
      default:
        return null;
    }
  }

  /// A calendar component of the entry's date (`0` year, `1` month, `2` day),
  /// or `0` when it has no usable date.
  ///
  /// The legacy field query reads an absent date as `0`, which is why `DAY<5`
  /// matches an undated entry.
  int _datePart(AvesEntry entry, int index) {
    final date = entry.bestDate;
    if (date == null) return 0;
    final (year, month, day) = calendar.ops.getYearMonthDay(date);
    return switch (index) {
      0 => year,
      1 => month,
      _ => day,
    };
  }

  static EntryPredicate? _numericTest(String op, num Function(AvesEntry) valueOf, num target) {
    return switch (op) {
      opEqual => (entry) => valueOf(entry) == target,
      opLower => (entry) => valueOf(entry) < target,
      opGreater => (entry) => valueOf(entry) > target,
      _ => null,
    };
  }

  /// Parses the `KEY<op>value` form, resolving its value once (bytes for
  /// `SIZE`), or null when the string is not a field query.
  ///
  /// A key whose value cannot be parsed, and a key without a predicate for the
  /// operation, fall back to the title search exactly as before.
  QueryField? _parseField(String upQuery) {
    final match = _fieldPattern.firstMatch(upQuery);
    if (match == null) return null;

    final key = match.group(1)?.trim();
    final op = match.group(2)?.trim();
    final valueString = match.group(3)?.trim();
    if (key == null || op == null || valueString == null) return null;

    switch (key) {
      case keyContentExtension:
        if (op != opEqual) return null;
        return QueryField(key: key, op: op, text: '.$valueString');
      case keyContentId:
        if (op != opEqual) return null;
        final contentId = int.tryParse(valueString);
        if (contentId == null) return null;
        return QueryField(key: key, op: op, value: contentId);
      case keyContentYear:
      case keyContentMonth:
      case keyContentDay:
      case keyContentWidth:
      case keyContentHeight:
        final value = int.tryParse(valueString);
        if (value == null) return null;
        return QueryField(key: key, op: op, value: value);
      case keyContentSize:
        final sizeMatch = _fileSizePattern.firstMatch(valueString);
        final digits = sizeMatch?.group(1)?.trim();
        if (digits == null) return null;
        final value = int.tryParse(digits);
        if (value == null) return null;
        return QueryField(key: key, op: op, value: applyFileSizeSuffix(sizeMatch?.group(2)?.trim(), value));
      default:
        return null;
    }
  }
}

/// A `KEY<op>value` query, resolved once by [QueryFilter].
///
/// [value] is the resolved number (bytes for `SIZE`); [text] carries the
/// resolved payload of the one text-valued key (`EXT`, dot included).
class QueryField {
  final String key;
  final String op;
  final int value;
  final String? text;

  const new({required this.key, required this.op, this.value = 0, this.text});
}
