import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The four number boxes of the custom-interval editor, in display order.
///
/// Kept apart from [WallpaperAdvanceInterval] because the editor edits fields,
/// not seconds: a value is decomposed into days/hours/minutes/seconds and the
/// boxes are summed back. Each box is capped at [maxFieldValue]; the total is
/// still bounded by the interval itself, so `1000 days` is rejected by
/// [isValid] rather than silently clamped.
@immutable
class WallpaperIntervalParts with Equatable {
  /// Upper bound of ONE box, matching what a numeric keyboard can express
  /// comfortably. `1000` is the largest value a box accepts, not a carry limit:
  /// `90` minutes is simply 90 minutes.
  static const int maxFieldValue = 1000;

  /// What the editor opens with when the caller's interval is off.
  ///
  /// Ten minutes is long enough to not drain the battery and short enough to
  /// see the wallpaper move while setting it up.
  static const WallpaperIntervalParts defaultTenMinutes = WallpaperIntervalParts(minutes: 10);

  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  const new({
    this.days = 0,
    this.hours = 0,
    this.minutes = 0,
    this.seconds = 0,
  });

  /// Splits [value] into whole days/hours/minutes/seconds, so an existing
  /// interval round-trips through the editor unchanged.
  static WallpaperIntervalParts fromSeconds(int value) {
    if (value <= 0) return const WallpaperIntervalParts();
    var rest = value;
    final days = rest ~/ Duration.secondsPerDay;
    rest -= days * Duration.secondsPerDay;
    final hours = rest ~/ Duration.secondsPerHour;
    rest -= hours * Duration.secondsPerHour;
    final minutes = rest ~/ Duration.secondsPerMinute;
    rest -= minutes * Duration.secondsPerMinute;
    return WallpaperIntervalParts(days: days, hours: hours, minutes: minutes, seconds: rest);
  }

  int get totalSeconds =>
      days * Duration.secondsPerDay + hours * Duration.secondsPerHour + minutes * Duration.secondsPerMinute + seconds;

  /// Whether every box is inside `0..maxFieldValue`.
  bool get isWithinFieldBounds => [days, hours, minutes, seconds].every((value) => value >= 0 && value <= maxFieldValue);

  /// Whether the sum is an interval the scheduler can use.
  ///
  /// `0` (off) is not offered here: Off is always a built-in option, so adding
  /// it through the editor would only duplicate it.
  bool get isValid =>
      isWithinFieldBounds &&
      totalSeconds >= WallpaperAdvanceInterval.minSeconds &&
      totalSeconds <= WallpaperAdvanceInterval.maxSeconds;

  @override
  List<Object?> get props => [days, hours, minutes, seconds];
}
