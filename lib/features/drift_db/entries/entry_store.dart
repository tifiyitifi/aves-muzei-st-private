import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/db_helpers.dart';
import 'package:aves/features/drift_db/entries/section_header.dart';
import 'package:aves/features/logging/log.dart';
import 'package:aves/features/logging/log_keys.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

const _log = AreaKeyLog(LogKeys.db);

/// Owns the `entry` table: CRUD, directory/origin loading, live search and
/// duplicate detection. Drift types never leave this store.
class EntryStore {
  static const _table = 'entry';
  static const _insertSliceMaxCount = 10000; // number of entries

  /// Physical name of the maintained directory column (pinned via
  /// `.named('directory')` in `EntriesTable`, mirroring the legacy camelCase
  /// pins for raw-map access).
  static const String directoryColumn = 'directory';

  final AppDatabase db;

  new(this.db);

  Future<int> maxId() async {
    final rows = await db.customSelect('SELECT MAX(id) AS maxId FROM $_table').get();
    return (rows.firstOrNull?.data['maxId'] as int?) ?? 0;
  }

  Future<void> clear() async {
    final count = await db.delete(db.entriesTable).go();
    _log.d('$runtimeType clear deleted $count rows');
  }

  Future<Set<AvesEntry>> load({int? origin, String? directory}) async {
    final variables = <Variable>[];
    var where = '';
    if (origin != null) {
      where = 'origin = ?';
      variables.add(Variable(origin));
    }

    final entries = <AvesEntry>{};
    if (directory != null) {
      final separator = pContext.separator;
      if (!directory.endsWith(separator)) {
        directory = '$directory$separator';
      }

      where = '${where.isNotEmpty ? '$where AND ' : ''}path LIKE ?';
      variables.add(Variable('$directory%'));
      final rows = await db.customSelect('SELECT * FROM $_table WHERE $where', variables: variables).get();

      final dirLength = directory.length;
      for (final row in rows) {
        // skip entries in subfolders
        final path = row.data['path'] as String?;
        if (path != null && !path.substring(dirLength).contains(separator)) {
          entries.add(AvesEntry.fromMap(row.data));
        }
      }
    } else {
      final rows = where.isNotEmpty ? await db.customSelect('SELECT * FROM $_table WHERE $where', variables: variables).get() : await selectAllRows(db, _table);
      for (final row in rows) {
        entries.add(AvesEntry.fromMap(row.data));
      }
    }

    return entries;
  }

  Future<Set<AvesEntry>> loadByIds(Set<int> ids) => selectByIds(db, _table, ids, AvesEntry.fromMap);

  /// Counts the entries matching the window predicate.
  ///
  /// Built on the same [_windowWhere] predicate as [loadWindow], so the total
  /// reported to the UI always matches the rows a full walk would return.
  Future<int> count({int? origin, String? directory, bool excludeTrashed = true, bool trashedOnly = false}) async {
    final where = _windowWhere(origin: origin, directory: directory, excludeTrashed: excludeTrashed, trashedOnly: trashedOnly);
    final rows = await db.customSelect('SELECT COUNT(*) AS n FROM $_table e ${where.sql}', variables: where.variables).get();
    return (rows.firstOrNull?.data['n'] as int?) ?? 0;
  }

  /// Loads one window of entries in collection order.
  ///
  /// `bestDate` mirrors `AvesEntry.bestDate`: the catalogued date first, then
  /// the source date, then the modification date. Secondary ordering is
  /// deterministic (`title`, then `id`) but only approximates the in-memory
  /// natural sort, which SQLite cannot express; items whose primary keys tie
  /// may sit in a different adjacency than in the legacy full-load path.
  ///
  /// The optional section predicates ([directoryEquals], [dateFromMillis] /
  /// [dateToMillis], [ratingEquals]) restrict the window to one section; they
  /// extend the same [_windowWhere] predicate, so section windows always agree
  /// with [loadSectionHeaders] and [count].
  Future<List<AvesEntry>> loadWindow({
    int? origin,
    String? directory,
    bool excludeTrashed = true,
    bool trashedOnly = false,
    String? directoryEquals,
    bool directoryEqualsNull = false,
    int? dateFromMillis,
    int? dateToMillis,
    int? ratingEquals,
    required SortFactor sort,
    required bool reverse,
    required int limit,
    required int offset,
  }) async {
    if (limit <= 0) return [];
    final where = _windowWhere(
      origin: origin,
      directory: directory,
      excludeTrashed: excludeTrashed,
      trashedOnly: trashedOnly,
      directoryEquals: directoryEquals,
      directoryEqualsNull: directoryEqualsNull,
      dateFromMillis: dateFromMillis,
      dateToMillis: dateToMillis,
      ratingEquals: ratingEquals,
    );
    final joinMetadata = sort == SortFactor.rating || ratingEquals != null;
    const bestDate = 'COALESCE(dt.dateMillis, e.sourceDateTakenMillis, e.dateModifiedMillis, 0)';
    final orderBy = switch (sort) {
      SortFactor.date => 'ORDER BY $bestDate ${_dir(descDefault: true, reverse: reverse)}, e.title ${_dir(descDefault: true, reverse: reverse)}, e.id ${_dir(descDefault: true, reverse: reverse)}',
      SortFactor.albumItemName => 'ORDER BY e.path ${_dir(descDefault: false, reverse: reverse)}, e.id ${_dir(descDefault: false, reverse: reverse)}',
      SortFactor.rating => 'ORDER BY COALESCE(m.rating, 0) ${_dir(descDefault: true, reverse: reverse)}, $bestDate ${_dir(descDefault: true, reverse: reverse)}, e.id ${_dir(descDefault: true, reverse: reverse)}',
      SortFactor.size => 'ORDER BY COALESCE(e.sizeBytes, 0) ${_dir(descDefault: true, reverse: reverse)}, $bestDate ${_dir(descDefault: true, reverse: reverse)}, e.id ${_dir(descDefault: true, reverse: reverse)}',
      SortFactor.duration => 'ORDER BY COALESCE(e.durationMillis, 0) ${_dir(descDefault: true, reverse: reverse)}, $bestDate ${_dir(descDefault: true, reverse: reverse)}, e.id ${_dir(descDefault: true, reverse: reverse)}',
      SortFactor.path => 'ORDER BY e.path ${_dir(descDefault: false, reverse: reverse)}, e.id ${_dir(descDefault: false, reverse: reverse)}',
      SortFactor.chipName || SortFactor.count => throw UnimplementedError('window loading is not defined for chip sorts: $sort'),
    };
    final rows = await db.customSelect(
      'SELECT e.*, dt.dateMillis AS dateMillis, t.path AS trashPath, t.dateMillis AS trashDateMillis FROM $_table e LEFT JOIN dateTaken dt ON dt.id = e.id LEFT JOIN trash t ON t.id = e.id${joinMetadata ? ' LEFT JOIN metadata m ON m.id = e.id' : ''} ${where.sql} $orderBy LIMIT ? OFFSET ?',
      variables: [...where.variables, Variable(limit), Variable(offset < 0 ? 0 : offset)],
    ).get();
    return [for (final row in rows) _entryFromWindowRow(row.data)];
  }

  /// `ASC`/`DESC` for a sort whose default direction is [descDefault],
  /// flipped when the collection is reversed (a whole-list reversal).
  static String _dir({required bool descDefault, required bool reverse}) => (descDefault != reverse) ? 'DESC' : 'ASC';

  AvesEntry _entryFromWindowRow(Map<String, Object?> data) {
    final entry = AvesEntry.fromMap(data);
    // Same source as `CollectionSource._savedDates`: the catalogued date.
    entry.catalogDateMillis = data['dateMillis'] as int?;
    // Trash rows carry their restore details so bin actions keep working on
    // windowed entries without a separate lookup.
    final trashPath = data['trashPath'] as String?;
    final trashDateMillis = data['trashDateMillis'] as int?;
    if (trashPath != null && trashDateMillis != null) {
      entry.trashDetails = TrashDetails(id: entry.id, path: trashPath, dateMillis: trashDateMillis);
    }
    return entry;
  }

  /// Loads one header per group of the window predicate, in display order.
  ///
  /// `month`/`day` use the Gregorian calendar via `strftime` on the device
  /// local time (same basis as `dateTimeFromMillis`). Non-Gregorian calendars
  /// resolve in the slice instead: it computes bucket boundaries with
  /// `calendar.ops` and issues bounded `COUNT` queries per bucket, so SQL
  /// never needs to understand those calendars.
  Future<List<SectionHeader>> loadSectionHeaders({
    int? origin,
    String? directory,
    bool excludeTrashed = true,
    bool trashedOnly = false,
    required SectionGrouping grouping,
    required bool reverse,
  }) async {
    final where = _windowWhere(origin: origin, directory: directory, excludeTrashed: excludeTrashed, trashedOnly: trashedOnly);
    switch (grouping) {
      case SectionGrouping.album:
        // `IS NULL` first: legacy sorts a null directory as `''` (first in
        // ASC, last after a whole-list reversal), while SQLite would sort
        // NULLs first in both directions.
        final dir = reverse ? 'DESC' : 'ASC';
        final rows = await db.customSelect(
          'SELECT e.directory AS k, COUNT(*) AS n FROM $_table e ${where.sql} GROUP BY e.directory ORDER BY e.directory IS NULL, e.directory $dir',
          variables: where.variables,
        ).get();
        return [for (final row in rows) SectionHeader.album(directory: row.data['k'] as String?, count: (row.data['n'] as int?) ?? 0)];
      case SectionGrouping.month:
      case SectionGrouping.day:
        const bestDateSecs = 'COALESCE(dt.dateMillis, e.sourceDateTakenMillis, e.dateModifiedMillis, 0) / 1000';
        final parts = grouping == SectionGrouping.month ? "strftime('%Y', $bestDateSecs, 'unixepoch', 'localtime') AS y, strftime('%m', $bestDateSecs, 'unixepoch', 'localtime') AS m" : "strftime('%Y', $bestDateSecs, 'unixepoch', 'localtime') AS y, strftime('%m', $bestDateSecs, 'unixepoch', 'localtime') AS m, strftime('%d', $bestDateSecs, 'unixepoch', 'localtime') AS d";
        final dir = reverse ? 'ASC' : 'DESC';
        final rows = await db.customSelect(
          'SELECT $parts, COUNT(*) AS n FROM $_table e LEFT JOIN dateTaken dt ON dt.id = e.id ${where.sql} GROUP BY y, m${grouping == SectionGrouping.day ? ', d' : ''} ORDER BY y $dir, m $dir${grouping == SectionGrouping.day ? ', d $dir' : ''}',
          variables: where.variables,
        ).get();
        return [
          for (final row in rows)
            if (grouping == SectionGrouping.month)
              SectionHeader.month(year: int.parse(row.data['y'] as String), month: int.parse(row.data['m'] as String), count: (row.data['n'] as int?) ?? 0)
            else
              SectionHeader.day(year: int.parse(row.data['y'] as String), month: int.parse(row.data['m'] as String), day: int.parse(row.data['d'] as String), count: (row.data['n'] as int?) ?? 0),
        ];
      case SectionGrouping.rating:
        final rows = await db.customSelect(
          'SELECT COALESCE(m.rating, 0) AS k, COUNT(*) AS n FROM $_table e LEFT JOIN metadata m ON m.id = e.id ${where.sql} GROUP BY k ORDER BY k ${reverse ? 'ASC' : 'DESC'}',
          variables: where.variables,
        ).get();
        return [for (final row in rows) SectionHeader.rating(rating: (row.data['k'] as int?) ?? 0, count: (row.data['n'] as int?) ?? 0)];
      case SectionGrouping.single:
        return [SectionHeader.single(count: await count(origin: origin, directory: directory, excludeTrashed: excludeTrashed, trashedOnly: trashedOnly))];
    }
  }

  /// Shared predicate for [count], [loadWindow] and [loadSectionHeaders].
  ///
  /// The directory clause matches direct children only (`dir/%` but not
  /// `dir/%/%`), mirroring the subfolder skip in [load]. The `LIKE` prefix is
  /// escaped so directories containing `%` or `_` filter literally.
  ({String sql, List<Variable> variables}) _windowWhere({
    int? origin,
    String? directory,
    bool excludeTrashed = true,
    bool trashedOnly = false,
    String? directoryEquals,
    bool directoryEqualsNull = false,
    int? dateFromMillis,
    int? dateToMillis,
    int? ratingEquals,
  }) {
    final conditions = <String>[];
    final variables = <Variable>[];
    if (origin != null) {
      conditions.add('e.origin = ?');
      variables.add(Variable(origin));
    }
    if (trashedOnly) {
      conditions.add('e.trashed != ?');
      variables.add(const Variable(0));
    } else if (excludeTrashed) {
      conditions.add('e.trashed = ?');
      variables.add(const Variable(0));
    }
    if (directory != null) {
      var prefix = directory;
      final separator = pContext.separator;
      if (!prefix.endsWith(separator)) {
        prefix = '$prefix$separator';
      }
      final escaped = prefix.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
      conditions.add("e.path LIKE ? ESCAPE '\\'");
      variables.add(Variable('$escaped%'));
      conditions.add("e.path NOT LIKE ? ESCAPE '\\'");
      variables.add(Variable('$escaped%/%'));
    }
    if (directoryEqualsNull) {
      conditions.add('e.directory IS NULL');
    } else if (directoryEquals != null) {
      conditions.add('e.directory = ?');
      variables.add(Variable(directoryEquals));
    }
    if (dateFromMillis != null || dateToMillis != null) {
      const bestDate = 'COALESCE(dt.dateMillis, e.sourceDateTakenMillis, e.dateModifiedMillis, 0)';
      if (dateFromMillis != null) {
        conditions.add('$bestDate >= ?');
        variables.add(Variable(dateFromMillis));
      }
      if (dateToMillis != null) {
        conditions.add('$bestDate < ?');
        variables.add(Variable(dateToMillis));
      }
    }
    if (ratingEquals != null) {
      conditions.add('COALESCE(m.rating, 0) = ?');
      variables.add(Variable(ratingEquals));
    }
    return (sql: conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}', variables: variables);
  }

  Future<void> insertAll(Set<AvesEntry> entries) async {
    if (entries.isEmpty) return;
    final stopwatch = Stopwatch()..start();
    var inserted = 0;
    // slice entries to avoid memory issues
    for (final slice in entries.slices(_insertSliceMaxCount)) {
      _log.d('$runtimeType inserting slice of [${inserted + 1}, ${inserted + slice.length}] entries');
      await db.batch((batch) {
        for (final entry in slice) {
          batchInsertReplace(batch, db.entriesTable, _toRowMap(entry));
        }
      });
      inserted += slice.length;
    }
    _log.d('$runtimeType insert complete in ${stopwatch.elapsed.inMilliseconds}ms for ${entries.length} entries');
  }

  Future<void> update(int id, AvesEntry entry) async {
    await db.batch((batch) {
      batch.deleteWhere(db.entriesTable, (t) => t.id.equals(id));
      batchInsertReplace(batch, db.entriesTable, _toRowMap(entry));
    });
  }

  /// Row map for writes: the upstream serializer plus the maintained
  /// `directory` column (see `MigrationV3`).
  static Map<String, Object?> _toRowMap(AvesEntry entry) => {
        ...entry.toDatabaseMap(),
        directoryColumn: directoryOf(entry.path),
      };

  /// Raw single-level parent directory of [path], or null for path-less rows.
  ///
  /// This is the exact value `AvesEntry.directory` feeds to `entryDirRepo`
  /// (before filesystem disambiguation), so header keys and row grouping agree.
  static String? directoryOf(String? path) => path == null ? null : pContext.dirname(path);

  Future<Set<AvesEntry>> searchLive(String query, {int? limit}) async {
    final variables = <Variable>[Variable('%$query%'), Variable('%$query%'), const Variable(0)];
    final limitClause = limit != null ? ' LIMIT ?' : '';
    if (limit != null) variables.add(Variable(limit));
    final rows = await db.customSelect(
      'SELECT * FROM $_table WHERE (title LIKE ? OR path LIKE ?) AND trashed = ? ORDER BY sourceDateTakenMillis DESC$limitClause',
      variables: variables,
    ).get();
    return rows.map((row) => AvesEntry.fromMap(row.data)).toSet();
  }

  Future<Set<AvesEntry>> searchDuplicates(int origin, Set<AvesEntry>? entries) async {
    var where = 'origin = ? AND trashed = ?';
    final variables = <Variable>[Variable(origin), const Variable(0)];
    if (entries != null) {
      where += ' AND contentId IN (${entries.map((v) => v.contentId).join(',')})';
    }
    final rows = await db.customSelect(
      'SELECT *, MAX(id) AS id FROM $_table WHERE $where GROUP BY contentId HAVING COUNT(id) > 1',
      variables: variables,
    ).get();
    final duplicates = rows.map((row) => AvesEntry.fromMap(row.data)).toSet();
    if (duplicates.isNotEmpty) {
      _log.d('$runtimeType found duplicates=$duplicates');
    }
    // returns most recent duplicate for each duplicated content ID
    return duplicates;
  }

  void deleteInBatch(Batch batch, int id) {
    batch.deleteWhere(db.entriesTable, (t) => t.id.equals(id));
  }
}
