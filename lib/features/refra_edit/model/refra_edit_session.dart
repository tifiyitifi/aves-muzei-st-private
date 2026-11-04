import 'package:aves/features/drift_db/app_database.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Why a session stopped being editable.
enum RefraEditSessionStatus {
  /// The copies still live in the staging directory.
  active,

  /// Every kept output was moved back to the source directory.
  moved,

  /// The user deleted the staged copies.
  discarded,
}

/// A copy-first edit session.
///
/// The session owns a staging directory; the source it was copied from is kept only as a
/// destination, never written to.
@immutable
class RefraEditSession extends Equatable {
  final String id;
  final int? sourceEntryId;
  final String sourceUri;
  final String sourcePath;
  final String sourceDirectory;
  final String sourceName;
  final String sourceMimeType;
  final String stagingDirectory;
  final String stagedUri;
  final DateTime createdAt;
  final RefraEditSessionStatus status;

  const new({
    required this.id,
    required this.sourceEntryId,
    required this.sourceUri,
    required this.sourcePath,
    required this.sourceDirectory,
    required this.sourceName,
    required this.sourceMimeType,
    required this.stagingDirectory,
    required this.stagedUri,
    required this.createdAt,
    required this.status,
  });

  factory fromRow(RefraEditSessionRow row) => RefraEditSession(
    id: row.id,
    sourceEntryId: row.sourceEntryId,
    sourceUri: row.sourceUri,
    sourcePath: row.sourcePath,
    sourceDirectory: row.sourceDirectory,
    sourceName: row.sourceName,
    sourceMimeType: row.sourceMimeType,
    stagingDirectory: row.stagingDirectory,
    stagedUri: row.stagedUri,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    status: RefraEditSessionStatus.values.firstWhere(
      (v) => v.name == row.status,
      orElse: () => RefraEditSessionStatus.active,
    ),
  );

  @override
  List<Object?> get props => [
    id,
    sourceEntryId,
    sourceUri,
    sourcePath,
    sourceDirectory,
    sourceName,
    sourceMimeType,
    stagingDirectory,
    stagedUri,
    createdAt,
    status,
  ];
}

/// How an output file was produced.
enum RefraEditOutputKind {
  /// The initial copy the editor worked on.
  staged,

  /// Written by the built-in editor (save a copy, RAW export).
  builtIn,

  /// Returned by a third-party editor.
  external,

  /// Found by rescanning the staging directory, origin unknown.
  unknown,
}

/// One file a session produced, counted as a result on the session page.
@immutable
class RefraEditOutput extends Equatable {
  final String id;
  final String sessionId;
  final String uri;
  final String path;
  final String fileName;
  final RefraEditOutputKind kind;
  final int sizeBytes;
  final DateTime createdAt;

  const new({
    required this.id,
    required this.sessionId,
    required this.uri,
    required this.path,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory fromRow(RefraEditOutputRow row) => RefraEditOutput(
    id: row.id,
    sessionId: row.sessionId,
    uri: row.uri,
    path: row.path,
    fileName: row.fileName,
    kind: RefraEditOutputKind.values.firstWhere(
      (v) => v.name == row.kind,
      orElse: () => RefraEditOutputKind.unknown,
    ),
    sizeBytes: row.sizeBytes,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );

  @override
  List<Object?> get props => [id, sessionId, uri, path, fileName, kind, sizeBytes, createdAt];
}
