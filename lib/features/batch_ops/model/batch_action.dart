import 'package:flutter/foundation.dart';

/// A batch tool the native engine knows how to apply.
///
/// The id is the contract with `BatchToolRegistry` on the Android side. Adding a
/// tool means adding an id here, a `BatchTool` there, and a catalog entry in the
/// view layer; nothing else in the pipeline needs to change.
enum BatchToolKind {
  recipe('refra.recipe'),
  filter('refra.filter'),
  adjust('refra.adjust'),
  rotate('refra.rotate'),
  flip('refra.flip'),
  crop('refra.crop'),
  resize('image.resize'),
  convert('image.convert'),
  footer('decorate.footer'),
  refreshTime('file.time');

  final String id;

  new(this.id);

  static BatchToolKind? tryParse(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// One configured action in a batch chain.
///
/// [settings] is the same plain map the native tool reads, so a profile is just
/// a list of these and serialization never needs a per-tool codec.
@immutable
class BatchAction {
  final BatchToolKind kind;
  final Map<String, Object?> settings;
  final bool enabled;

  const new({
    required this.kind,
    this.settings = const {},
    this.enabled = true,
  });

  Map<String, Object?> toToolSpec() => {'id': kind.id, 'settings': settings};

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'settings': settings,
    'enabled': enabled,
  };

  static BatchAction? tryFromJson(Map<String, Object?> json) {
    final kind = BatchToolKind.tryParse(json['kind'] as String?);
    if (kind == null) return null;
    final rawSettings = json['settings'];
    final settings = rawSettings is Map ? rawSettings.map((key, value) => MapEntry(key.toString(), value)) : <String, Object?>{};
    return BatchAction(kind: kind, settings: settings, enabled: json['enabled'] != false);
  }

  BatchAction copyWith({Map<String, Object?>? settings, bool? enabled}) => BatchAction(
    kind: kind,
    settings: settings ?? this.settings,
    enabled: enabled ?? this.enabled,
  );
}

/// Factories for the actions the run sheet can add.
abstract final class BatchActions {
  static BatchAction recipe(List<Map<String, Object?>> ops) => BatchAction(kind: BatchToolKind.recipe, settings: {'ops': ops});

  static BatchAction filter(String name, {double intensity = 1}) => BatchAction(kind: BatchToolKind.filter, settings: {'name': name, 'intensity': intensity});

  static BatchAction adjust(String name, {double value = 0}) => BatchAction(kind: BatchToolKind.adjust, settings: {'name': name, 'value': value});

  static BatchAction rotate({double angle = 90}) => BatchAction(kind: BatchToolKind.rotate, settings: {'angle': angle});

  static BatchAction flip({bool horizontal = true}) => BatchAction(kind: BatchToolKind.flip, settings: {'horizontal': horizontal});

  static BatchAction crop({double left = 0, double top = 0, double right = 1, double bottom = 1}) => BatchAction(
    kind: BatchToolKind.crop,
    settings: {
      'rect': [left, top, right, bottom],
    },
  );

  static BatchAction resize({int? maxLongEdge, int? percent}) => BatchAction(
    kind: BatchToolKind.resize,
    settings: {'maxLongEdge': maxLongEdge, 'percent': percent},
  );

  static BatchAction convert({String format = 'keep', int quality = 100}) => BatchAction(kind: BatchToolKind.convert, settings: {'format': format, 'quality': quality});

  static BatchAction footer({String? text, int bandHeightPercent = 8, int textSizePercent = 55, bool atTop = false}) => BatchAction(
    kind: BatchToolKind.footer,
    settings: {
      if (text != null && text.isNotEmpty) 'text': text,
      'bandHeightPercent': bandHeightPercent,
      'textSizePercent': textSizePercent,
      'atTop': atTop,
    },
  );

  static BatchAction refreshTime() => const BatchAction(kind: BatchToolKind.refreshTime, settings: {'enabled': true});
}
