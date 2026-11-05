import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/refra_edit/model/refra_edit_paths.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Why a session stopped being editable.
enum RefraEditSessionStatus {
  /// The copies still live in the staging directory.
  active,

  /// Every kept output was moved back to the source directory.
  moved,

  /// The session's files were copied back; the staged copies are still there.
  copied,

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

/// One file a session is still holding, as listed on the records page.
///
/// The same file can be recorded more than once: the move operation and the media
/// scanner name the same volume differently (`external_primary` vs `external`), so
/// [rowIds] keeps every alias. Deleting a record removes the file once and forgets
/// all of its rows.
@immutable
class RefraEditRecord extends Equatable {
  /// Identity of the file, independent of the volume alias used by each row.
  final String key;

  /// Every output row describing this file.
  final Set<String> rowIds;

  final String sessionId;
  final String uri;
  final String fileName;
  final RefraEditOutputKind kind;
  final int sizeBytes;
  final DateTime createdAt;

  /// The session the file belongs to, when its row still resolves one.
  final RefraEditSession? session;

  const new({
    required this.key,
    required this.rowIds,
    required this.sessionId,
    required this.uri,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.createdAt,
    required this.session,
  });

  /// Absolute directory the file can be moved or copied back to.
  String get sourceDirectory => session?.sourceDirectory ?? '';

  /// Whether the record knows a destination that is not the staging tree itself.
  ///
  /// Only files the editor staged may leave the staging tree, and only towards the
  /// folder their source came from: a session started on a staging file has no
  /// meaningful destination.
  bool get canTransferBack {
    final directory = sourceDirectory;
    return directory.isNotEmpty && !isRefraEditStagingPath(directory);
  }

  @override
  List<Object?> get props => [key, rowIds, sessionId, uri, fileName, kind, sizeBytes, createdAt, session];
}
