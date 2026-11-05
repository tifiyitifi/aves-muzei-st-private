import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:flutter/foundation.dart';

/// One source image in a job.
@immutable
class BatchItem {
  final int entryId;
  final String uri;
  final String displayName;
  final String? mimeType;

  const new({
    required this.entryId,
    required this.uri,
    required this.displayName,
    this.mimeType,
  });

  Map<String, Object?> toMap() => {
    'entryId': entryId,
    'uri': uri,
    'displayName': displayName,
    'mimeType': mimeType,
  };
}

/// Where the processed images go and how they are named.
///
/// The default is the fork's batch folder. Copy-share will later pass its own
/// folder without changing the engine.
@immutable
class BatchOutput {
  static const String defaultRelativePath = 'Pictures/aves_batch';

  final String relativePath;
  final String namePattern;
  final String format;
  final int quality;

  const new({
    this.relativePath = defaultRelativePath,
    this.namePattern = '{name}',
    this.format = 'keep',
    this.quality = 100,
  });

  Map<String, Object?> toMap() => {
    'relativePath': relativePath,
    'namePattern': namePattern,
    'format': format,
    'quality': quality,
  };
}

@immutable
class BatchJob {
  final String jobId;
  final List<BatchItem> items;
  final List<BatchAction> actions;
  final BatchOutput output;

  const new({
    required this.jobId,
    required this.items,
    required this.actions,
    this.output = const BatchOutput(),
  });

  Map<String, Object?> toMap() => {
    'jobId': jobId,
    'items': items.map((item) => item.toMap()).toList(),
    'tools': actions.where((action) => action.enabled).map((action) => action.toToolSpec()).toList(),
    'output': output.toMap(),
  };
}

enum BatchEventType {
  jobStarted,
  itemStarted,
  itemProgress,
  itemDone,
  itemFailed,
  jobDone;

  static BatchEventType? tryParse(String? value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// One event of the native job stream.
@immutable
class BatchEvent {
  final BatchEventType type;
  final String? jobId;
  final int? index;
  final int? entryId;
  final String? uri;
  final String? message;
  final int? itemCount;
  final int? done;
  final int? failed;
  final bool cancelled;

  const new({
    required this.type,
    this.jobId,
    this.index,
    this.entryId,
    this.uri,
    this.message,
    this.itemCount,
    this.done,
    this.failed,
    this.cancelled = false,
  });

  static BatchEvent? tryFromMap(Map<Object?, Object?> map) {
    final type = BatchEventType.tryParse(map['type'] as String?);
    if (type == null) return null;
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    return BatchEvent(
      type: type,
      jobId: map['jobId'] as String?,
      index: asInt(map['index']),
      entryId: asInt(map['entryId']),
      uri: map['uri'] as String?,
      message: map['message'] as String?,
      itemCount: asInt(map['itemCount']),
      done: asInt(map['done']),
      failed: asInt(map['failed']),
      cancelled: map['cancelled'] == true,
    );
  }
}
