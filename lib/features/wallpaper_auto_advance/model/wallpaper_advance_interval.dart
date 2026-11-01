import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A wallpaper auto-advance interval, stored as plain seconds.
///
/// A value object rather than an enum: the option catalog is user-editable, so
/// the set of valid values is data, not code. `0` means off; any other value is
/// clamped to [minSeconds]..[maxSeconds] when it enters the app.
@immutable
class WallpaperAdvanceInterval with Equatable {
  /// Below this, the WorkManager chain cannot keep up and only wakes the device
  /// for nothing. Exposed so tests and the add dialog share one bound.
  static const int minSeconds = 3;

  /// 30 days. The scheduler handles it (`long` milliseconds), but real rotations
  /// stop at days, so the shipped defaults stay shorter.
  static const int maxSeconds = 30 * 24 * 60 * 60;

  static const WallpaperAdvanceInterval off = WallpaperAdvanceInterval(0);

  final int seconds;

  const new(this.seconds);

  bool get enabled => seconds > 0;

  bool get isOff => seconds <= 0;

  bool get isWithinBounds => seconds == 0 || (seconds >= minSeconds && seconds <= maxSeconds);

  /// Converts a stored or entered number, keeping arbitrary custom values.
  ///
  /// The previous enum-based reader returned `null` for a value it did not know,
  /// which silently turned a user's custom interval into 「never」.
  static WallpaperAdvanceInterval fromSeconds(Object? value) {
    // Only whole seconds are meaningful; a fractional or string value is a
    // corrupt setting, not a custom option.
    final raw = value is num && value == value.roundToDouble() ? value.toInt() : null;
    if (raw == null || raw <= 0) return off;
    return WallpaperAdvanceInterval(raw.clamp(minSeconds, maxSeconds));
  }

  @override
  List<Object?> get props => [seconds];

  @override
  String toString() => 'WallpaperAdvanceInterval($seconds s)';
}
