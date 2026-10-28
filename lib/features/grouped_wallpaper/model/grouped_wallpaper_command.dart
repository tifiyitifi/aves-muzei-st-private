/// A command the notification sends to the wallpaper engine.
///
/// The notification lives in Kotlin, but every change that needs a bake or a
/// database write is owned by Dart, so the two sides share these names: the
/// native action strings are exactly the enum names, and an unknown string is
/// ignored instead of failing the run.
enum GroupedWallpaperCommand {
  /// Shows the photo before the current one, when it is still known.
  previousArtwork,

  /// Shows the next queued photo. The renderer usually promotes it natively;
  /// this is the headless fallback.
  nextArtwork,

  /// Makes the next enabled group current.
  nextGroup,

  /// Makes the previous enabled group current.
  previousGroup,

  /// Stops advancing the wallpaper, keeping the current frame.
  pause,

  /// Resumes advancing from the current frame.
  resume;

  static GroupedWallpaperCommand? tryParse(Object? value) {
    if (value is! String) return null;
    for (final command in values) {
      if (command.name == value) return command;
    }
    return null;
  }
}
