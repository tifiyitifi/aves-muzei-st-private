/// Categories grouping the metadata settings surface (v2).
///
/// Deliberately separate from the upstream `SettingsSection` abstraction. The
/// order matches the upstream settings list, with [wallpaper] (the fork's own
/// category) just before [advanced] (the engine selector), which stays last;
/// unmigrated categories fall back to a fork-owned copy of the legacy section.
enum SettingsCategory {
  navigation,
  thumbnails,
  viewer,
  video,
  privacy,
  accessibility,
  display,
  language,
  wallpaper,
  advanced,
}
