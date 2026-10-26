import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Granularity of a "time to now" window (`TIME2NOW`).
///
/// Two units cover every preset the search assist offers; a week is written as
/// `7d` rather than its own unit so the persisted token stays unambiguous.
enum RelativeTimeUnit {
  hour,
  day;

  /// Milliseconds in one unit.
  int get millis => switch (this) {
        hour => Duration.millisecondsPerHour,
        day => Duration.millisecondsPerDay,
      };

  /// Suffix of the persisted token (`3h`, `7d`).
  String get token => switch (this) {
        hour => 'h',
        day => 'd',
      };

  static RelativeTimeUnit? parse(String? value) => switch (value) {
        'h' || 'hour' || 'hours' => hour,
        'd' || 'day' || 'days' => day,
        _ => null,
      };
}

/// A parsed `TIME2NOW` token: an amount and its unit.
///
/// The token is the persisted form (`3h`, `12h`, `7d`, `30d`), so a saved
/// search keeps meaning "the last N" instead of freezing the instant it was
/// created.
@immutable
class TimeToNow extends Equatable {
  final int amount;
  final RelativeTimeUnit unit;

  const new({required this.amount, required this.unit});

  /// The window length in milliseconds.
  int get millis => amount * unit.millis;

  String get token => '$amount${unit.token}';

  static final _pattern = RegExp(r'^(\d{1,4})\s*([hd])$', caseSensitive: false);

  /// Parses `3h`, `12h`, `7d`, `30d` (case-insensitive). Null when the token is
  /// malformed or the amount is zero: a zero-width window matches nothing, which
  /// is never what the user meant.
  static TimeToNow? parse(String? raw) {
    if (raw == null) return null;
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final amount = int.tryParse(match.group(1)!);
    // The pattern is case-insensitive, so the captured unit still carries the
    // user's case.
    final unit = RelativeTimeUnit.parse(match.group(2)?.toLowerCase());
    if (amount == null || amount <= 0 || unit == null) return null;
    return TimeToNow(amount: amount, unit: unit);
  }

  @override
  List<Object?> get props => [amount, unit];
}
