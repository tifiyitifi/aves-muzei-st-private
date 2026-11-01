import 'package:aves/features/wallpaper_auto_advance/model/wallpaper_advance_interval.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:material_ui/material_ui.dart';

/// Formats an interval with the largest unit that divides it exactly.
///
/// The option list is data-driven, so the label cannot be a `switch` over an
/// enum any more: 90 seconds reads as seconds, 90 minutes as minutes, and a
/// custom 30-day value as days.
String wallpaperAdvanceIntervalLabel(BuildContext context, WallpaperAdvanceInterval value) {
  final l10n = context.l10n;
  if (!value.enabled) return l10n.muzeiWallpaperAutoAdvanceOff;
  final seconds = value.seconds;
  if (seconds % Duration.secondsPerDay == 0) return l10n.muzeiWallpaperAutoAdvanceDays(seconds ~/ Duration.secondsPerDay);
  if (seconds % Duration.secondsPerHour == 0) return l10n.muzeiWallpaperAutoAdvanceHours(seconds ~/ Duration.secondsPerHour);
  if (seconds % Duration.secondsPerMinute == 0) return l10n.muzeiWallpaperAutoAdvanceMinutes(seconds ~/ Duration.secondsPerMinute);
  return l10n.muzeiWallpaperAutoAdvanceSeconds(seconds);
}
