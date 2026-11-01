/// How many baked frames the live renderer keeps on the GPU.
///
/// The frame on screen is always kept, whatever this says: dropping it is what
/// shows the grey placeholder. The switch only decides whether the neighbours
/// that make a tap instant are worth their memory, which is why it is a global
/// wallpaper switch rather than a group effect (the renderer fades and keeps
/// frames that may belong to different groups).
enum GroupedWallpaperFrameRetention {
  /// Follow the home scroll effect: its frames are the widest to keep.
  auto,

  /// Keep the current, previous and next frames.
  all,

  /// Keep the frame on screen only; a tap decodes its target first.
  displayed,
  ;

  /// What a state written before the switch existed gets.
  ///
  /// Those builds decoded and kept every slot, so keeping them is both the
  /// faithful default and the one that makes a tap instant.
  static const GroupedWallpaperFrameRetention defaultRetention = all;

  static GroupedWallpaperFrameRetention tryParse(Object? value) {
    for (final retention in values) {
      if (retention.name == value) return retention;
    }
    return defaultRetention;
  }
}
