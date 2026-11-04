/// Which implementation handles media file operations (move, copy, rename).
///
/// [v1] is the upstream pipeline: every entry resolves its storage APIs on its
/// own and a Media Store scan is awaited right after each file. [v2] is the
/// fork's batched pipeline: it resolves the target directory once per group,
/// prefers a Media Store field update (no scan at all) and scans leftovers in a
/// single batch. Both emit the same events, so switching engines never changes
/// how the collection is updated.
enum MediaOpEngine {
  v1,
  v2;

  /// New installs run the fast pipeline. The legacy one stays reachable from
  /// Advanced, and keeping it as the default would leave the fork's main
  /// optimization unused on every device.
  static const MediaOpEngine defaultEngine = MediaOpEngine.v2;

  static MediaOpEngine? tryParse(String? name) {
    for (final value in MediaOpEngine.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
