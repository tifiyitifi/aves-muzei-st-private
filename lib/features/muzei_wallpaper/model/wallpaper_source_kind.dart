/// Where a wallpaper artwork comes from.
enum WallpaperSourceKind {
  /// A user-defined collection scope (albums, tags, filters, ...).
  myPhotos,

  /// One explicitly chosen entry.
  single;

  /// Parses a persisted enum name, returning null for unknown values.
  static WallpaperSourceKind? tryParse(String? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}
