import 'dart:math' as math;

import 'package:aves/features/muzei_wallpaper/model/wallpaper_framing.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Muzei-compatible effect values for one surface (home or lock).
///
/// Values are kept on Muzei's scales: blur and grey span `0..500`, dim spans
/// `0..255`. The baker converts them to pixels/alpha; the native renderer only
/// crossfades between the sharp and effect images.
@immutable
class WallpaperEffects with Equatable {
  static const int maxBlur = 500;
  static const int maxDim = 255;
  static const int maxGrey = 500;

  /// Our defaults leave the photo untouched: no blur, no dim, no greyscale.
  ///
  /// This differs from Muzei on purpose (its defaults are 250/128/0); it is not
  /// a bug or an oversight. The wallpaper exists to show the photo, and every
  /// effect is opt-in. Muzei's values remain one tap away, as [muzeiDefaults].
  static const int defaultBlur = 0;
  static const int defaultDim = 0;
  static const int defaultGrey = 0;

  /// Muzei's own defaults, offered as an explicit preset on the effects screen.
  ///
  /// Kept separate from the constructor defaults so neither can drift into the
  /// other: [muzeiDefaults] is a product decision inherited from Muzei, while
  /// the defaults above are ours.
  static const WallpaperEffects muzeiDefaults = WallpaperEffects(blur: 250, dim: 128, grey: 0);

  final int blur;
  final int dim;
  final int grey;

  const new({
    this.blur = defaultBlur,
    this.dim = defaultDim,
    this.grey = defaultGrey,
  }) : assert(blur >= 0 && blur <= maxBlur),
       assert(dim >= 0 && dim <= maxDim),
       assert(grey >= 0 && grey <= maxGrey);

  static int clampBlur(int value) => value < 0 ? 0 : (value > maxBlur ? maxBlur : value);

  static int clampDim(int value) => value < 0 ? 0 : (value > maxDim ? maxDim : value);

  static int clampGrey(int value) => value < 0 ? 0 : (value > maxGrey ? maxGrey : value);

  bool get isIdentity => blur == 0 && dim == 0 && grey == 0;

  /// Blur radius in full-resolution pixels before the baker downsamples.
  ///
  /// Matches Muzei's `screenHeight * blur * 0.0001` radius. `ImageFilter.blur`
  /// takes a sigma, hence the halving; [downscale] is the baker's reduction
  /// factor, so the visual radius stays the same after upscaling.
  double sigmaFor(double screenHeightPx, {double downscale = 1}) {
    final radius = screenHeightPx * blur * 0.0001;
    final factor = downscale <= 0 ? 1.0 : downscale;
    return math.max(0, radius / 2 / factor);
  }

  /// Black overlay alpha for a sampled artwork darkness in `0..1`.
  ///
  /// Darker images need less dimming to reach the same contrast, so the alpha
  /// follows Muzei's `0.5 + 0.5 * sqrt(darkness)` curve.
  int dimAlpha(double darkness) {
    final d = darkness.clamp(0.0, 1.0).toDouble();
    final alpha = (dim * (0.5 + 0.5 * math.sqrt(d))).round();
    return alpha < 0 ? 0 : (alpha > maxDim ? maxDim : alpha);
  }

  /// `ColorFilter.matrix` desaturation for the grey slider.
  List<double> get desaturationMatrix {
    final s = (grey / maxGrey).clamp(0.0, 1.0).toDouble();
    final inv = 1 - s;
    const lr = 0.299;
    const lg = 0.587;
    const lb = 0.114;
    return <double>[
      inv + s * lr, s * lg, s * lb, 0, 0, //
      s * lr, inv + s * lg, s * lb, 0, 0, //
      s * lr, s * lg, inv + s * lb, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  WallpaperEffects copyWith({int? blur, int? dim, int? grey}) => WallpaperEffects(
    blur: clampBlur(blur ?? this.blur),
    dim: clampDim(dim ?? this.dim),
    grey: clampGrey(grey ?? this.grey),
  );

  Map<String, Object?> toJsonMap() => {'blur': blur, 'dim': dim, 'grey': grey};

  static WallpaperEffects fromJsonMap(Map<String, Object?> json) {
    return WallpaperEffects(
      blur: clampBlur(_int(json['blur']) ?? defaultBlur),
      dim: clampDim(_int(json['dim']) ?? defaultDim),
      grey: clampGrey(_int(json['grey']) ?? defaultGrey),
    );
  }

  static int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  @override
  List<Object?> get props => [blur, dim, grey];
}

/// Home and lock effects, plus Muzei's optional link toggle.
///
/// For the grouped wallpaper this is also the group's display configuration: it
/// carries [homeScrollEffect], the rotation threshold and the per-surface framing
/// (rotation and image fit). The plain Muzei wallpaper shares the type but leaves
/// the framing at its defaults, so those fields serialize with neutral values
/// there.
@immutable
class WallpaperEffectsConfig with Equatable {
  /// The default long/short ratio a mismatched photo needs to be worth a turn.
  ///
  /// The grouped wallpaper exposes it as a slider: 1.2 is the tuned value, 2.0
  /// turns only a very wide photo, and anything at or below 1.0 would turn even
  /// nearly square ones for no visible gain.
  static const double defaultRotationThreshold = 1.2;
  static const double minRotationThreshold = 1.05;
  static const double maxRotationThreshold = 2.0;

  /// [value] clamped into the range the slider offers, with a bad value (NaN,
  /// infinity, a stale record) falling back to the default.
  static double clampRotationThreshold(double value) {
    if (value.isNaN || value.isInfinite) return defaultRotationThreshold;
    return value.clamp(minRotationThreshold, maxRotationThreshold).toDouble();
  }

  final WallpaperEffects home;
  final WallpaperEffects lock;
  final bool link;

  /// Whether home frames keep the photo's whole width for the launcher to pan.
  ///
  /// It belongs to the group like the effect values, so a group can pan while
  /// another stays still. The lock screen never pans, so there is no lock
  /// counterpart: offering one would be a switch with no visible effect.
  ///
  /// `null` means "not chosen yet": the first use follows the device (see
  /// [resolvedHomeScrollEffect]), and a manual toggle stores a definite value so
  /// later launcher changes never override the user's choice.
  final bool? homeScrollEffect;

  /// The long/short ratio a mismatched photo must reach to be turned.
  ///
  /// Kept on the group rather than per surface: it is one rule ("is the turn
  /// worth it?"), and two sliders would let the home and lock screens disagree
  /// about the same photo for no reason.
  final double rotationThreshold;

  /// Rotation and fit of the home surface.
  final WallpaperFraming framingHome;

  /// Rotation and fit of the lock surface.
  ///
  /// Deliberately independent of [link]: linking is about the effect sliders,
  /// while the lock screen's framing is judged against the lock surface.
  final WallpaperFraming framingLock;

  const new({
    this.home = const WallpaperEffects(),
    this.lock = const WallpaperEffects(),
    this.link = false,
    this.homeScrollEffect,
    this.rotationThreshold = defaultRotationThreshold,
    this.framingHome = const WallpaperFraming(),
    this.framingLock = const WallpaperFraming(),
  }) : assert(rotationThreshold > 1 && rotationThreshold <= maxRotationThreshold, 'a threshold at or below 1 would turn nearly square photos');

  /// The lock-surface values actually rendered.
  WallpaperEffects get effectiveLock => link ? home : lock;

  /// Whether the user has never touched the home scroll switch.
  bool get scrollEffectIsAuto => homeScrollEffect == null;

  /// The switch as the page shows it: the user's choice, or whether the launcher
  /// can pan while nothing was chosen.
  bool resolvedHomeScrollEffect({required bool pans}) => homeScrollEffect ?? pans;

  /// [this] with [value] stored on the surface being edited.
  ///
  /// With the link on the two surfaces are one setting, so both are written:
  /// storing only one side would leave the other stale for when the link is
  /// turned off again.
  WallpaperEffectsConfig applyTo({required bool onLock, required WallpaperEffects value}) {
    if (link) return copyWith(home: value, lock: value);
    return onLock ? copyWith(lock: value) : copyWith(home: value);
  }

  /// [this] linked or unlinked, copying the edited surface onto the other.
  ///
  /// Linking in Muzei makes the two surfaces equal from that moment on, which is
  /// why the values of the surface being edited win.
  WallpaperEffectsConfig withLink({required bool linked, required bool fromLock}) {
    if (!linked) return copyWith(link: false);
    final value = fromLock ? effectiveLock : home;
    return copyWith(home: value, lock: value, link: true);
  }

  WallpaperEffectsConfig copyWith({
    WallpaperEffects? home,
    WallpaperEffects? lock,
    bool? link,
    bool? homeScrollEffect,
    double? rotationThreshold,
    WallpaperFraming? framingHome,
    WallpaperFraming? framingLock,
  }) => WallpaperEffectsConfig(
    home: home ?? this.home,
    lock: lock ?? this.lock,
    link: link ?? this.link,
    homeScrollEffect: homeScrollEffect ?? this.homeScrollEffect,
    rotationThreshold: clampRotationThreshold(rotationThreshold ?? this.rotationThreshold),
    framingHome: framingHome ?? this.framingHome,
    framingLock: framingLock ?? this.framingLock,
  );

  /// [this] with [value] stored on the surface being edited.
  ///
  /// The link toggle does not copy framing: it is edited per surface, and the
  /// lock screen's framing is judged against its own surface.
  WallpaperEffectsConfig withFraming({required bool onLock, required WallpaperFraming value}) => onLock ? copyWith(framingLock: value) : copyWith(framingHome: value);

  Map<String, Object?> toJsonMap() => {
    'home': home.toJsonMap(),
    'lock': lock.toJsonMap(),
    'link': link,
    'homeScrollEffect': homeScrollEffect,
    'rotationThreshold': rotationThreshold,
    'framingHome': framingHome.toJsonMap(),
    'framingLock': framingLock.toJsonMap(),
  };

  /// Reads a stored config.
  ///
  /// [legacyScrollEffect] is the app-wide switch groups used before it moved
  /// into the config: a group that never stored its own value keeps the choice
  /// the user already made instead of silently turning panning on or off. `null`
  /// means there was no app-wide value either, i.e. a fresh install, which stays
  /// automatic.
  ///
  /// [defaultFraming] is what a missing framing record reads. The grouped
  /// wallpaper passes its own default (a mismatched photo is turned by default);
  /// the plain Muzei wallpaper keeps the identity framing it never draws.
  static WallpaperEffectsConfig fromJsonMap(
    Map<String, Object?> json, {
    bool? legacyScrollEffect,
    WallpaperFraming defaultFraming = const WallpaperFraming(),
  }) {
    // A stored `null` is a deliberate "automatic", not a missing record: only an
    // absent key falls back to the legacy app-wide switch.
    final scrollEffect = json.containsKey('homeScrollEffect') ? (json['homeScrollEffect'] is bool ? json['homeScrollEffect'] as bool : null) : legacyScrollEffect;
    final framingHome = _map(json['framingHome']);
    final framingLock = _map(json['framingLock']);
    return WallpaperEffectsConfig(
      home: WallpaperEffects.fromJsonMap(_map(json['home']) ?? const {}),
      lock: WallpaperEffects.fromJsonMap(_map(json['lock']) ?? const {}),
      link: json['link'] == true,
      homeScrollEffect: scrollEffect,
      rotationThreshold: clampRotationThreshold(_double(json['rotationThreshold']) ?? defaultRotationThreshold),
      framingHome: framingHome == null ? defaultFraming : WallpaperFraming.fromJsonMap(framingHome),
      framingLock: framingLock == null ? defaultFraming : WallpaperFraming.fromJsonMap(framingLock),
    );
  }

  static double? _double(Object? value) => value is num ? value.toDouble() : null;

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  @override
  List<Object?> get props => [home, lock, link, homeScrollEffect, rotationThreshold, framingHome, framingLock];
}
