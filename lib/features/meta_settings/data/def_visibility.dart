import 'package:aves/model/device.dart';
import 'package:aves/model/settings/settings.dart';

/// Registry of runtime predicates that gate a `SettingDef`'s visibility.
///
/// Availability depends on the device and on other settings, so it cannot be a
/// static catalog field: a def references a key here instead.
abstract final class DefVisibility {
  /// Hidden when the TV layout is active (mirrors the upstream Display section).
  static const String notTv = 'not_tv';

  /// Shown only when the device supports dynamic color.
  static const String dynamicColor = 'dynamic_color';

  /// Hidden on actual televisions.
  static const String notTelevision = 'not_television';

  static final Map<String, bool Function()> _predicates = {
    notTv: () => !settings.useTvLayout,
    dynamicColor: () => device.isDynamicColorAvailable,
    notTelevision: () => !device.isTelevision,
  };

  static Set<String> get registeredKeys => _predicates.keys.toSet();

  static bool isRegistered(String key) => _predicates.containsKey(key);

  /// A def with no availability key is always visible.
  static bool isVisible(String? key) => key == null || (_predicates[key]?.call() ?? true);
}
