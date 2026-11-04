import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class ImageOpEvent extends Equatable {
  final bool success, skipped;
  final String uri;

  @override
  List<Object?> get props => [success, skipped, uri];

  const new({
    required this.success,
    required this.skipped,
    required this.uri,
  });

  factory fromMap(Map map) {
    final skipped = map['skipped'] ?? false;
    return ImageOpEvent(
      success: (map['success'] ?? false) || skipped,
      skipped: skipped,
      uri: map['uri'],
    );
  }
}

@immutable
class MoveOpEvent extends ImageOpEvent {
  final Map newFields;
  final bool deleted;

  /// Outcome of the system write request, reported at most once per operation:
  /// `granted`, `denied`, `unavailable`, or null for the legacy pipeline.
  final String? permission;

  /// Storage path the entry took: `mediastore`, `file`, `saf`, or null for the
  /// legacy pipeline.
  final String? strategy;

  @override
  List<Object?> get props => [success, skipped, uri, newFields, deleted, permission, strategy];

  const new({
    required super.success,
    required super.skipped,
    required super.uri,
    required this.newFields,
    required this.deleted,
    this.permission,
    this.strategy,
  });

  factory fromMap(Map map) {
    final newFields = map['newFields'] ?? {};
    final skipped = (map['skipped'] ?? false) || (newFields['skipped'] ?? false);
    final deleted = (map['deleted'] ?? false) || (newFields['deleted'] ?? false);
    return MoveOpEvent(
      success: (map['success'] ?? false) || skipped,
      skipped: skipped,
      uri: map['uri'],
      newFields: newFields,
      deleted: deleted,
      permission: map['permission'] as String?,
      strategy: map['strategy'] as String?,
    );
  }
}

@immutable
class ExportOpEvent extends MoveOpEvent {
  final int? pageId;

  @override
  List<Object?> get props => [success, skipped, uri, pageId, newFields];

  const new({
    required super.success,
    required super.skipped,
    required super.uri,
    this.pageId,
    required super.newFields,
  }) : super(
         deleted: false,
       );

  factory fromMap(Map map) {
    final newFields = map['newFields'] ?? {};
    final skipped = (map['skipped'] ?? false) || (newFields['skipped'] ?? false);
    return ExportOpEvent(
      success: (map['success'] ?? false) || skipped,
      skipped: skipped,
      uri: map['uri'],
      pageId: map['pageId'],
      newFields: newFields,
    );
  }
}
