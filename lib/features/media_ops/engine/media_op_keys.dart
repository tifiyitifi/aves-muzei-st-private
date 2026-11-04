/// `SharedPreferences` keys owned by the media operations feature.
///
/// They live outside both settings stores (like the settings-engine gate) so
/// they stay readable before a store is chosen and survive switches between the
/// legacy (v1) and metadata (v2) settings engines.
abstract final class MediaOpKeys {
  /// Which pipeline handles move/copy/rename.
  static const String engine = 'media_ops.engine';

  /// Whether a denied system write request may be retried on a later operation.
  ///
  /// Cleared from the settings surface: a denial usually means the user wants
  /// to be left alone, but it can also be a mis-tap, so it must be undoable.
  static const String allowPermissionPrompt = 'media_ops.allow_permission_prompt';
}
