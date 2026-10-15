/// Registry of the app-wide log channels.
///
/// A channel is a hierarchical, dot-separated key: `log.<domain>[.<sub>]`. A
/// gate set on a parent key applies to every child that does not define its
/// own, so opening `log.db` also turns on `log.db.catalog`.
///
/// Only genuinely cross-cutting channels belong here. A channel owned by a
/// single feature is declared next to that feature (in its own slice), so
/// adding logging never means editing a shared catch-all.
abstract final class LogKeys {
  /// App entry point, lifecycle, and global startup.
  static const String app = 'log.app';

  /// Local media database layer.
  static const String db = 'log.db';

  /// Settings load, save, and migration.
  static const String settings = 'log.settings';

  /// Media scanning and cataloguing.
  static const String media = 'log.media';

  /// Every cross-cutting channel, in declaration order. Debug builds open all
  /// of them so development logs are never silently dropped.
  static const List<String> all = [app, db, settings, media];
}
