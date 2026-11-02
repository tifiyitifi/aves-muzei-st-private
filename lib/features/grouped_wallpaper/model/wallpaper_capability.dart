/// Where the system actually draws this app's grouped live wallpaper.
///
/// Android only separates the lock screen's live wallpaper from API 34, and an
/// OEM picker may ignore the surface the user picked. `lock` therefore means
/// "the home screen kept a static wallpaper", not "the user chose the lock
/// screen": that is why it is the one answer that rules out home panning.
enum WallpaperHost {
  home,
  lock,
  both,
  none;

  /// Persisted by name across the channel: the Kotlin side writes the names.
  static WallpaperHost parse(Object? raw) {
    for (final host in values) {
      if (host.name == raw) return host;
    }
    return none;
  }

  /// Whether the home screen draws this service.
  bool get hasHome => this == home || this == both;
}

/// What a capability probe concluded.
///
/// The distinction between [unsupported] and [unknown] is the whole point: only
/// a positive "this cannot work" may change the baked frame, because a wrong
/// [unsupported] would silently remove a working phone's scroll effect.
enum CapabilityVerdict {
  supported,
  unsupported,
  unknown,
}

/// Whether a launcher puts a third-party live wallpaper on its home screen and
/// pans it with the home pages.
///
/// Deliberately small: a wrong entry only costs the user one extra confirmation
/// before applying, but entries are added only with evidence, not by guessing
/// every OEM. [panVerdict] never consults this list, so a wrong entry can never
/// narrow a frame.
const fixedWallpaperLaunchers = <String>{
  // MIUI / HyperOS: the bundled picker binds a third-party service to the lock
  // screen only, and the home wallpaper is a static image that never pans.
  'com.miui.home',
};

/// What the device can do, as last measured by the native service.
///
/// It is a snapshot, not a lease: [scrollStep] is filled by the launcher's first
/// `onOffsetsChanged`, so the same device answers `unknown` before it and
/// `unsupported`/`supported` afterwards.
class WallpaperCapability {
  /// Where this service is bound right now.
  final WallpaperHost host;

  /// The default home package, empty when the platform could not resolve one.
  final String launcherPackage;

  /// `Build.MODEL`, used only to remember which devices were already warned.
  final String deviceModel;

  /// The system's wallpaper scroll setting where the OEM exposes one.
  ///
  /// `0` is a launcher that was told not to scroll; null means the key is
  /// absent on this ROM, which is the normal case outside MIUI.
  final int? scrollSpan;

  /// Fraction of the scroll range one home page takes.
  ///
  /// `0` means the launcher never pans, `> 0` means it does, and null means no
  /// offset callback has arrived yet.
  final double? scrollStep;

  /// Whether the launcher ever moved its offset between callbacks.
  ///
  /// A step of zero is not proof that panning is impossible: some launchers
  /// scroll the wallpaper while reporting no step, and only the moving offset
  /// shows it.
  final bool scrollOffsetMoved;

  const new({
    this.host = WallpaperHost.none,
    this.launcherPackage = '',
    this.deviceModel = '',
    this.scrollSpan,
    this.scrollStep,
    this.scrollOffsetMoved = false,
  });

  /// Nothing measured: a desktop host, a failing channel, or a service that has
  /// not started yet. It must never narrow a frame.
  static const unknown = WallpaperCapability();

  /// Reads the platform's answer.
  ///
  /// Anything missing degrades to [unknown] instead of "unsupported": a failed
  /// probe is not evidence that the phone cannot pan.
  static WallpaperCapability parse(Map<Object?, Object?>? raw) {
    if (raw == null) return unknown;
    final span = raw['scrollSpan'];
    final step = raw['scrollStep'];
    return WallpaperCapability(
      host: WallpaperHost.parse(raw['host']),
      launcherPackage: raw['launcher'] is String ? raw['launcher'] as String : '',
      deviceModel: raw['model'] is String ? raw['model'] as String : '',
      scrollSpan: span is num ? span.toInt() : null,
      scrollStep: step is num ? step.toDouble() : null,
      scrollOffsetMoved: raw['scrollOffsetMoved'] == true,
    );
  }

  /// Whether the home screen can host and pan this wallpaper.
  ///
  /// Order matters. Real evidence that the wallpaper follows the home pages — a
  /// positive step, or an offset that visibly moved — is first-hand and wins
  /// over every second-hand signal: an OEM setting that still says "no scroll"
  /// must not overrule a launcher that is visibly panning. Only when nothing
  /// pans (or there is no home host to pan) does the verdict say
  /// [CapabilityVerdict.unsupported].
  CapabilityVerdict get panVerdict {
    if (host == WallpaperHost.lock) return CapabilityVerdict.unsupported;
    if (!host.hasHome) return CapabilityVerdict.unknown;
    final step = scrollStep;
    if (step != null && step > 0) return CapabilityVerdict.supported;
    if (scrollOffsetMoved) return CapabilityVerdict.supported;
    if (scrollSpan == 0) return CapabilityVerdict.unsupported;
    if (step == 0) return CapabilityVerdict.unsupported;
    return CapabilityVerdict.unknown;
  }

  /// Whether the home screen is known not to run a third-party live wallpaper.
  ///
  /// This only drives the pre-apply warning: a wrong answer here is a dialog the
  /// user dismisses, never a changed frame.
  CapabilityVerdict get hostVerdict {
    if (host.hasHome) return CapabilityVerdict.supported;
    if (fixedWallpaperLaunchers.contains(launcherPackage)) return CapabilityVerdict.unsupported;
    return CapabilityVerdict.unknown;
  }

  /// Whether frames should keep the photo's whole width for the launcher to pan.
  ///
  /// Unknown stays wide on purpose: a phone whose answer is not measured yet
  /// keeps a panning frame it may not need, which is far cheaper than taking the
  /// effect away from a phone that does pan.
  bool get bakesWide => panVerdict != CapabilityVerdict.unsupported;

  /// Whether applying the wallpaper deserves a one-time warning.
  bool get warnsBeforeApply => hostVerdict == CapabilityVerdict.unsupported || panVerdict == CapabilityVerdict.unsupported;

  /// Identity of the device + launcher pair the warning was shown on.
  ///
  /// Changing the launcher asks again, because the new launcher may pan where
  /// the old one did not.
  String get warningKey => '$deviceModel|$launcherPackage';
}
