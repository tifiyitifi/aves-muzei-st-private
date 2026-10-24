import 'dart:math' as math;

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
@immutable
class WallpaperEffectsConfig with Equatable {
  final WallpaperEffects home;
  final WallpaperEffects lock;
  final bool link;

  const new({
    this.home = const WallpaperEffects(),
    this.lock = const WallpaperEffects(),
    this.link = false,
  });

  /// The lock-surface values actually rendered.
  WallpaperEffects get effectiveLock => link ? home : lock;

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
  }) => WallpaperEffectsConfig(
    home: home ?? this.home,
    lock: lock ?? this.lock,
    link: link ?? this.link,
  );

  Map<String, Object?> toJsonMap() => {
    'home': home.toJsonMap(),
    'lock': lock.toJsonMap(),
    'link': link,
  };

  static WallpaperEffectsConfig fromJsonMap(Map<String, Object?> json) {
    return WallpaperEffectsConfig(
      home: WallpaperEffects.fromJsonMap(_map(json['home']) ?? const {}),
      lock: WallpaperEffects.fromJsonMap(_map(json['lock']) ?? const {}),
      link: json['link'] == true,
    );
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  @override
  List<Object?> get props => [home, lock, link];
}
