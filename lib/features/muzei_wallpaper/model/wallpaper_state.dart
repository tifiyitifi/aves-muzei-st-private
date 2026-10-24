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
///
/// [current] → [next] → [next2] is the promotion queue. The native renderer
/// promotes [next] on a wallpaper tap and [next2] on the following one, so two
/// consecutive taps need no bake; Dart refills the freed slots afterwards.
@immutable
class WallpaperState with Equatable {
  static const int currentVersion = 1;

  /// How many recently shown artworks are remembered.
  ///
  /// Used both for the empty-slot fallback and to keep the random ordering from
  /// repeating itself too soon. Fifty entries cost no disk (metadata only) and
  /// give a small library a real "no repeat" window, where Muzei keeps up to a
  /// hundred; five was too small to be noticeable.
  static const int maxRecent = 50;

  final int version;
  final int generation;
  final String sourceRevision;
  final int current;
  final int next;

  /// The second artwork baked ahead, promotable after [next].
  ///
  /// `-1` when only one artwork is prefetched (the default before the
  /// two-ahead option existed) or when the deeper bake has not finished yet.
  final int next2;

  final List<WallpaperSlot> slots;

  /// Artworks the wallpaper has shown, newest first.
  ///
  /// Only metadata: the baked paths belong to a slot, and a later bake recycles
  /// that slot, so a stored path would silently resolve to another artwork.
  /// When the queue is empty (first run, wallpaper cleared, every slot dropped
  /// because its photo was deleted), the page uses this to show the last
  /// artwork that still exists on disk instead of an empty screen.
  final List<WallpaperArtwork> recent;

  /// Highest entry id the wallpaper has shown.
  ///
  /// Muzei's `maxLoadedArtworkId`: anything with a larger id was added after the
  /// wallpaper last moved, so the "new photos in order" ordering serves it
  /// first. Ids come from MediaStore and grow with insertion, which is exactly
  /// the feed order Muzei relies on.
  final int newestEntryId;

  final WallpaperEffectsConfig effects;
  final WallpaperGestures gestures;
  final WallpaperTarget target;

  const new({
    this.version = currentVersion,
    this.generation = 0,
    this.sourceRevision = '',
    this.current = -1,
    this.next = -1,
    this.next2 = -1,
    this.slots = const [],
    this.recent = const [],
    this.newestEntryId = 0,
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

  WallpaperSlot? get next2Slot => slotById(next2);

  /// The slots baked ahead of [current], in promotion order.
  List<int> get queue => [current, next, next2].where((id) => id >= 0).toList();

  bool get hasCurrent => currentSlot != null;

  WallpaperState copyWith({
    int? version,
    int? generation,
    String? sourceRevision,
    int? current,
    int? next,
    int? next2,
    List<WallpaperSlot>? slots,
    List<WallpaperArtwork>? recent,
    int? newestEntryId,
    WallpaperEffectsConfig? effects,
    WallpaperGestures? gestures,
    WallpaperTarget? target,
  }) => WallpaperState(
    version: version ?? this.version,
    generation: generation ?? this.generation,
    sourceRevision: sourceRevision ?? this.sourceRevision,
    current: current ?? this.current,
    next: next ?? this.next,
    next2: next2 ?? this.next2,
    slots: slots ?? this.slots,
    recent: recent ?? this.recent,
    newestEntryId: newestEntryId ?? this.newestEntryId,
    effects: effects ?? this.effects,
    gestures: gestures ?? this.gestures,
    target: target ?? this.target,
  );

  /// [recent] with [artwork] moved to the front, de-duplicated and capped.
  ///
  /// The slot file paths are dropped on purpose: `recent` outlives the slot the
  /// artwork was baked into. The bake metrics (`width`/`height`/`darkness`) go
  /// with them, because they describe that same bake.
  static List<WallpaperArtwork> promoteRecent(List<WallpaperArtwork> recent, WallpaperArtwork? artwork) {
    if (artwork == null) return recent;
    final metadata = WallpaperArtwork(
      entryId: artwork.entryId,
      uri: artwork.uri,
      title: artwork.title,
      byline: artwork.byline,
      attribution: artwork.attribution,
      dateMillis: artwork.dateMillis,
    );
    return [
      metadata,
      ...recent.where((existing) => existing.entryId != metadata.entryId),
    ].take(maxRecent).toList(growable: false);
  }

  Map<String, Object?> toJsonMap() => {
    'version': version,
    'generation': generation,
    'sourceRevision': sourceRevision,
    'current': current,
    'next': next,
    'next2': next2,
    'slots': slots.map((slot) => slot.toJsonMap()).toList(),
    'recent': recent.map((artwork) => artwork.toJsonMap()).toList(),
    'newestEntryId': newestEntryId,
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
    final next2 = _int(json['next2']);
    final newestEntryId = _int(json['newestEntryId']);

    final recent = <WallpaperArtwork>[];
    final seenRecent = <int>{};
    final rawRecent = json['recent'];
    if (rawRecent is List) {
      for (final rawArtwork in rawRecent) {
        if (rawArtwork is! Map || recent.length >= maxRecent) continue;
        final artwork = WallpaperArtwork.tryFromJsonMap(
          rawArtwork.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (artwork != null && seenRecent.add(artwork.entryId)) recent.add(artwork);
      }
    }

    return WallpaperState(
      version: version!,
      generation: generation != null && generation >= 0 ? generation : 0,
      sourceRevision: json['sourceRevision'] is String ? json['sourceRevision'] as String : '',
      current: current != null && current >= -1 ? current : -1,
      next: next != null && next >= -1 ? next : -1,
      next2: next2 != null && next2 >= -1 ? next2 : -1,
      slots: List.unmodifiable(slots),
      recent: List.unmodifiable(recent),
      newestEntryId: newestEntryId != null && newestEntryId > 0 ? newestEntryId : 0,
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
  List<Object?> get props => [version, generation, sourceRevision, current, next, next2, slots, recent, newestEntryId, effects, gestures, target];
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
