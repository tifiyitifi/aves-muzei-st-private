/// Which settings engine is authoritative.
///
/// [v1] is the upstream `SharedPreferences` store and settings UI, kept as a
/// lossless rollback path. [v2] is the fork-only metadata engine (Drift-backed
/// storage plus the fork's own replicated settings surface).
enum SettingsEngineVersion {
  v1,
  v2;

  /// The engine a fresh install (and, after the seeding step, an upgrading
  /// install) runs on.
  static const SettingsEngineVersion defaultVersion = SettingsEngineVersion.v2;

  static SettingsEngineVersion? tryParse(String? name) {
    for (final value in SettingsEngineVersion.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
