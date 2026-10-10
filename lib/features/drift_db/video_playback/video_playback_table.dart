import 'package:drift/drift.dart';

class VideoPlaybackTable extends Table {
  @override
  String get tableName => 'videoPlayback';

  IntColumn get id => integer()();
  IntColumn get resumeTimeMillis => integer().named('resumeTimeMillis').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
