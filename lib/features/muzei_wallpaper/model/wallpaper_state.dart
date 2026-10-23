import 'package:aves/features/muzei_wallpaper/model/wallpaper_artwork.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_effects.dart';
import 'package:aves/features/muzei_wallpaper/model/wallpaper_gestures.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Which system surface a state applies to.
enum WallpaperTarget {
  home,
  lock,
  homeLock;

  static WallpaperTarget? tryParse(String? value) {
    for (final target in values) {
      if (target.name == value) return target;
    }
    return null;
  }
}

/// Dart-owned `state.json`.
///
/// This is the contract between the Flutter control plane and the native
/// renderer. Only Dart writes it; the native side writes [WallpaperRuntime]
/// instead. Keep parsing tolerant so a partially written file can never crash
/// the wallpaper service.
@immutable
class WallpaperState with Equatable {
  static const int currentVersion = 1;

  final int version;
  final int generation;
  final String sourceRevision;
  final int current;
  final int next;
  final List<WallpaperSlot> slots;
  final WallpaperEffectsConfig effects;
  final WallpaperGestures gestures;
  final WallpaperTarget target;

  const new({
    this.version = currentVersion,
    this.generation = 0,
    this.sourceRevision = '',
    this.current = -1,
    this.next = -1,
    this.slots = const [],
    this.effects = const WallpaperEffectsConfig(),
    this.gestures = const WallpaperGestures(),
    this.target = WallpaperTarget.homeLock,
  });

  WallpaperSlot? slotById(int id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  WallpaperSlot? get currentSlot => slotById(current);

  WallpaperSlot? get nextSlot => slotById(next);

  bool get hasCurrent => currentSlot != null;

  WallpaperState copyWith({
    int? version,
    int? generation,
    String? sourceRevision,
    int? current,
    int? next,
    List<WallpaperSlot>? slots,
    WallpaperEffectsConfig? effects,
    WallpaperGestures? gestures,
    WallpaperTarget? target,
  }) => WallpaperState(
    version: version ?? this.version,
    generation: generation ?? this.generation,
    sourceRevision: sourceRevision ?? this.sourceRevision,
    current: current ?? this.current,
    next: next ?? this.next,
    slots: slots ?? this.slots,
    effects: effects ?? this.effects,
    gestures: gestures ?? this.gestures,
    target: target ?? this.target,
  );

  Map<String, Object?> toJsonMap() => {
    'version': version,
    'generation': generation,
    'sourceRevision': sourceRevision,
    'current': current,
    'next': next,
    'slots': slots.map((slot) => slot.toJsonMap()).toList(),
    'effects': effects.toJsonMap(),
    'gestures': gestures.toJsonMap(),
    'target': target.name,
  };

  static WallpaperState? fromJsonMap(Map<String, Object?> json) {
    final version = _int(json['version']);
    if (version != currentVersion) return null;

    final slots = <WallpaperSlot>[];
    final seenIds = <int>{};
    final rawSlots = json['slots'];
    if (rawSlots is List) {
      for (final rawSlot in rawSlots) {
        if (rawSlot is! Map) continue;
        final slot = WallpaperSlot.tryFromJsonMap(
          rawSlot.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (slot != null && seenIds.add(slot.id)) slots.add(slot);
      }
    }

    final generation = _int(json['generation']);
    final current = _int(json['current']);
    final next = _int(json['next']);
    return WallpaperState(
      version: version!,
      generation: generation != null && generation >= 0 ? generation : 0,
      sourceRevision: json['sourceRevision'] is String ? json['sourceRevision'] as String : '',
      current: current != null && current >= -1 ? current : -1,
      next: next != null && next >= -1 ? next : -1,
      slots: List.unmodifiable(slots),
      effects: WallpaperEffectsConfig.fromJsonMap(_map(json['effects']) ?? const {}),
      gestures: WallpaperGestures.fromJsonMap(_map(json['gestures']) ?? const {}),
      target: WallpaperTarget.tryParse(json['target'] is String ? json['target'] as String : null) ?? WallpaperTarget.homeLock,
    );
  }

  static int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  @override
  List<Object?> get props => [version, generation, sourceRevision, current, next, slots, effects, gestures, target];
}

/// Native-owned `runtime.json`.
///
/// The native renderer may advance locally before Dart has baked the next
/// artwork, so it records the slot it is showing plus a refill request. A
/// generation mismatch means the file predates the latest [WallpaperState] and
/// must be ignored.
@immutable
class WallpaperRuntime with Equatable {
  final int generation;
  final int current;
  final int next;
  final bool refillRequested;

  const new({
    required this.generation,
    required this.current,
    required this.next,
    this.refillRequested = false,
  });

  static const WallpaperRuntime empty = WallpaperRuntime(
    generation: -1,
    current: -1,
    next: -1,
  );

  bool get hasCurrent => current >= 0;

  bool matches(WallpaperState state) => generation == state.generation;

  WallpaperRuntime copyWith({
    int? generation,
    int? current,
    int? next,
    bool? refillRequested,
  }) => WallpaperRuntime(
    generation: generation ?? this.generation,
    current: current ?? this.current,
    next: next ?? this.next,
    refillRequested: refillRequested ?? this.refillRequested,
  );

  Map<String, Object?> toJsonMap() => {
    'generation': generation,
    'current': current,
    'next': next,
    'refillRequested': refillRequested,
  };

  static WallpaperRuntime? fromJsonMap(Map<String, Object?> json) {
    final generation = WallpaperState._int(json['generation']);
    if (generation == null) return null;
    return WallpaperRuntime(
      generation: generation,
      current: WallpaperState._int(json['current']) ?? -1,
      next: WallpaperState._int(json['next']) ?? -1,
      refillRequested: json['refillRequested'] == true,
    );
  }

  @override
  List<Object?> get props => [generation, current, next, refillRequested];
}
