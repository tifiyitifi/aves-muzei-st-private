import 'dart:convert';

import 'package:aves/features/batch_ops/model/batch_action.dart';
import 'package:aves/features/batch_ops/model/batch_paths.dart';
import 'package:aves/features/drift_db/app_database.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Lifecycle of one recorded result.
enum BatchResultStatus {
  /// Written to the results folder and still waiting for a decision.
  pending,

  /// The result was applied to its source (replaced it or moved back).
  applied,

  /// The result row outlived its file, e.g. the user deleted it from the album.
  discarded;

  static BatchResultStatus parse(String? value) => values.firstWhere((status) => status.name == value, orElse: () => pending);
}

/// What a second run on the same source does with the first result.
enum BatchResultMode {
  /// Keep only the newest pending result of a source.
  replacePrevious,

  /// Keep every result, naming them `{name}_{date}`.
  keepVersions;

  static BatchResultMode parse(String? value) => values.firstWhere((mode) => mode.name == value, orElse: () => replacePrevious);
}

/// Which run a saved profile is for.
enum BatchProfileKind {
  /// Normal batch processing, output to the results folder.
  batch,

  /// Copy & share, output to the share folder (wired in the next step).
  share;

  static BatchProfileKind parse(String? value) => values.firstWhere((kind) => kind.name == value, orElse: () => batch);
}

/// One file batch processing produced, with enough of its source to act on it.
@immutable
class BatchResult extends Equatable {
  final String id;
  final String jobId;

  final int? sourceEntryId;
  final String sourceUri;
  final String sourcePath;
  final String sourceDirectory;
  final String sourceName;

  final String resultUri;
  final String resultPath;
  final String resultFileName;
  final String resultMimeType;
  final int resultSizeBytes;

  final String actionsJson;
  final DateTime createdAt;
  final BatchResultStatus status;

  const new({
    required this.id,
    required this.jobId,
    required this.sourceEntryId,
    required this.sourceUri,
    required this.sourcePath,
    required this.sourceDirectory,
    required this.sourceName,
    required this.resultUri,
    required this.resultPath,
    required this.resultFileName,
    required this.resultMimeType,
    required this.resultSizeBytes,
    required this.actionsJson,
    required this.createdAt,
    required this.status,
  });

  factory fromRow(BatchResultRow row) => BatchResult(
    id: row.id,
    jobId: row.jobId,
    sourceEntryId: row.sourceEntryId,
    sourceUri: row.sourceUri,
    sourcePath: row.sourcePath,
    sourceDirectory: row.sourceDirectory,
    sourceName: row.sourceName,
    resultUri: row.resultUri,
    resultPath: row.resultPath,
    resultFileName: row.resultFileName,
    resultMimeType: row.resultMimeType,
    resultSizeBytes: row.resultSizeBytes,
    actionsJson: row.actionsJson,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    status: BatchResultStatus.parse(row.status),
  );

  /// Whether a source is known well enough to be overwritten by this result.
  bool get canReplaceSource => sourceUri.isNotEmpty;

  /// Whether the recorded source directory is a real destination.
  ///
  /// A source that lived in the results folder itself has no meaningful folder
  /// to move back to: moving it there would just rename a result in place.
  bool get canMoveBack => sourceDirectory.isNotEmpty && !isBatchResultsPath(sourceDirectory);

  /// Name without its extension, used to build the replacement name.
  String get sourceBaseName => sourceName.contains('.') ? sourceName.substring(0, sourceName.lastIndexOf('.')) : sourceName;

  @override
  List<Object?> get props => [
    id,
    jobId,
    sourceEntryId,
    sourceUri,
    sourcePath,
    sourceDirectory,
    sourceName,
    resultUri,
    resultPath,
    resultFileName,
    resultMimeType,
    resultSizeBytes,
    actionsJson,
    createdAt,
    status,
  ];
}

/// A saved chain of actions the run sheet can reuse.
@immutable
class BatchProfile extends Equatable {
  final String id;
  final String name;
  final String actionsJson;
  final BatchProfileKind kind;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const new({
    required this.id,
    required this.name,
    required this.actionsJson,
    required this.kind,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory fromRow(BatchProfileRow row) => BatchProfile(
    id: row.id,
    name: row.name,
    actionsJson: row.actionsJson,
    kind: BatchProfileKind.parse(row.kind),
    sortOrder: row.sortOrder,
    isActive: row.isActive,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
  );

  /// The enabled actions this profile runs.
  List<BatchAction> get actions => decodeBatchActions(actionsJson);

  BatchProfile copyWith({
    String? name,
    String? actionsJson,
    int? sortOrder,
    bool? isActive,
    DateTime? updatedAt,
  }) => BatchProfile(
    id: id,
    name: name ?? this.name,
    actionsJson: actionsJson ?? this.actionsJson,
    kind: kind,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [id, name, actionsJson, kind, sortOrder, isActive, createdAt, updatedAt];
}

/// Encodes a profile's action chain.
///
/// Disabled actions are kept on purpose: they are configuration the user may
/// re-enable later, and the run filters on [BatchAction.enabled].
String encodeBatchActions(List<BatchAction> actions) => jsonEncode([for (final action in actions) action.toJson()]);

/// Decodes a profile's action chain, dropping entries this build no longer knows.
List<BatchAction> decodeBatchActions(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final raw in decoded)
      if (raw is Map) BatchAction.tryFromJson(raw.map((key, value) => MapEntry(key.toString(), value))),
  ].nonNulls.toList(growable: false);
}
