import 'package:equatable/equatable.dart';

/// How section headers group entries. `single` needs no query (one header for
/// the whole window predicate); every other value maps to a `GROUP BY`.
enum SectionGrouping {
  album,
  month,
  day,
  rating,
  single,
}

/// One section header: its grouping key plus the entry count.
///
/// Labels render from the key alone (album path, year/month/day, rating), so
/// dragging the scrollbar never triggers a row fetch. Covers and
/// representatives resolve later through window queries.
class SectionHeader extends Equatable {
  final SectionGrouping grouping;

  /// Album grouping: raw `directory` (may be null for path-less rows).
  final String? directory;

  /// Month/day grouping: calendar fields in the device time zone.
  final int? year;
  final int? month;
  final int? day;

  /// Rating grouping: `COALESCE(metadata.rating, 0)`.
  final int? rating;

  final int count;

  const new({
    required this.grouping,
    this.directory,
    this.year,
    this.month,
    this.day,
    this.rating,
    required this.count,
  });

  factory album({required String? directory, required int count}) =>
      SectionHeader(grouping: SectionGrouping.album, directory: directory, count: count);

  factory month({required int year, required int month, required int count}) =>
      SectionHeader(grouping: SectionGrouping.month, year: year, month: month, count: count);

  factory day({required int year, required int month, required int day, required int count}) =>
      SectionHeader(grouping: SectionGrouping.day, year: year, month: month, day: day, count: count);

  factory rating({required int rating, required int count}) =>
      SectionHeader(grouping: SectionGrouping.rating, rating: rating, count: count);

  factory single({required int count}) => SectionHeader(grouping: SectionGrouping.single, count: count);

  @override
  List<Object?> get props => [grouping, directory, year, month, day, rating, count];
}
