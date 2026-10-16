import 'package:aves/features/drift_db/app_database.dart';
import 'package:aves/features/drift_db/filter_summary/hidden_exclusion.dart';
import 'package:aves/features/drift_db/filter_summary/summary_rows.dart';
import 'package:drift/drift.dart';

/// DB-backed filter summaries: per-album/tag/location aggregates plus the
/// most recent entry id per group, without materializing entries.
///
/// All queries share one predicate shape: non-trashed rows plus the caller
/// supplied [SummaryExclusion]. `bestDate` mirrors `AvesEntry.bestDate` (and
/// `EntryStore.loadWindow`): catalogued date first, then source date, then
/// modification date. Ties break by larger id so the recent entry is
/// deterministic; item adjacency inside a tie may differ from the legacy
/// natural sort, which SQLite cannot express.
///
/// Drift types never leave this store: callers only see [summary_rows].
class FilterSummaryStore {
  final AppDatabase db;

  new(this.db);

  /// `COALESCE(dt.dateMillis, e.sourceDateTakenMillis, e.dateModifiedMillis, 0)`
  static const String _bestDate = 'COALESCE(dt.dateMillis, e.sourceDateTakenMillis, e.dateModifiedMillis, 0)';

  static const String _joins = 'FROM entry e LEFT JOIN dateTaken dt ON dt.id = e.id LEFT JOIN metadata m ON m.id = e.id LEFT JOIN address a ON a.id = e.id';

  String _where(SummaryExclusion exclusion) {
    const base = 'WHERE e.trashed = 0';
    return exclusion.isEmpty ? base : '$base AND ${exclusion.sql}';
  }

  List<Variable> _variables(SummaryExclusion exclusion) => exclusion.variables;

  Future<List<AlbumSummaryRow>> albumRows(SummaryExclusion exclusion) async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT e.directory AS k, COUNT(*) OVER w AS n, COALESCE(SUM(e.sizeBytes) OVER w, 0) AS s, MAX($_bestDate) OVER w AS md, '
          'FIRST_VALUE(e.id) OVER (PARTITION BY e.directory ORDER BY $_bestDate DESC, e.id DESC) AS rid '
          '$_joins ${_where(exclusion)} AND e.directory IS NOT NULL WINDOW w AS (PARTITION BY e.directory) ORDER BY k ASC',
          variables: _variables(exclusion),
        )
        .get();
    return [
      for (final row in rows)
        AlbumSummaryRow(
          directory: row.data['k'] as String,
          count: (row.data['n'] as int?) ?? 0,
          sizeBytes: (row.data['s'] as int?) ?? 0,
          maxBestDate: (row.data['md'] as int?) ?? 0,
          recentId: row.data['rid'] as int,
        ),
    ];
  }

  Future<List<TagSummaryRow>> tagRows(SummaryExclusion exclusion) async {
    // `xmpSubjects` stores `;`-joined tags (see `AvesEntry.tags`); the
    // recursive CTE splits them back into one row per (entry, tag).
    const cte = '''WITH RECURSIVE split(id, tag, rest) AS (
SELECT t.id, '', COALESCE(t.xmpSubjects, '') || ';' FROM metadata t
UNION ALL
SELECT id, SUBSTR(rest, 1, INSTR(rest, ';') - 1), SUBSTR(rest, INSTR(rest, ';') + 1) FROM split WHERE rest != ''
), tags AS (SELECT DISTINCT id, tag FROM split WHERE tag != '') ''';
    final rows = await db
        .customSelect(
          '${cte}SELECT DISTINCT g.tag AS k, COUNT(*) OVER w AS n, COALESCE(SUM(e.sizeBytes) OVER w, 0) AS s, MAX($_bestDate) OVER w AS md, '
          'FIRST_VALUE(e.id) OVER (PARTITION BY g.tag ORDER BY $_bestDate DESC, e.id DESC) AS rid '
          'FROM tags g JOIN entry e ON e.id = g.id LEFT JOIN dateTaken dt ON dt.id = e.id LEFT JOIN metadata m ON m.id = e.id LEFT JOIN address a ON a.id = e.id '
          '${_where(exclusion)} WINDOW w AS (PARTITION BY g.tag) ORDER BY k ASC',
          variables: _variables(exclusion),
        )
        .get();
    return [
      for (final row in rows)
        TagSummaryRow(
          tag: row.data['k'] as String,
          count: (row.data['n'] as int?) ?? 0,
          sizeBytes: (row.data['s'] as int?) ?? 0,
          maxBestDate: (row.data['md'] as int?) ?? 0,
          recentId: row.data['rid'] as int,
        ),
    ];
  }

  Future<List<CountrySummaryRow>> countryRows(SummaryExclusion exclusion) async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT a.countryCode AS k, MAX(a.countryName) OVER w AS nm, COUNT(*) OVER w AS n, COALESCE(SUM(e.sizeBytes) OVER w, 0) AS s, MAX($_bestDate) OVER w AS md, '
          'FIRST_VALUE(e.id) OVER (PARTITION BY a.countryCode ORDER BY $_bestDate DESC, e.id DESC) AS rid '
          "$_joins ${_where(exclusion)} AND a.countryCode IS NOT NULL AND a.countryCode != '' WINDOW w AS (PARTITION BY a.countryCode) ORDER BY k ASC",
          variables: _variables(exclusion),
        )
        .get();
    return [
      for (final row in rows)
        CountrySummaryRow(
          code: row.data['k'] as String,
          name: row.data['nm'] as String?,
          count: (row.data['n'] as int?) ?? 0,
          sizeBytes: (row.data['s'] as int?) ?? 0,
          maxBestDate: (row.data['md'] as int?) ?? 0,
          recentId: row.data['rid'] as int,
        ),
    ];
  }

  Future<List<StateSummaryRow>> stateRows(SummaryExclusion exclusion) async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT a.countryCode AS cc, a.adminArea AS nm, COUNT(*) OVER w AS n, COALESCE(SUM(e.sizeBytes) OVER w, 0) AS s, MAX($_bestDate) OVER w AS md, '
          'FIRST_VALUE(e.id) OVER (PARTITION BY a.countryCode, a.adminArea ORDER BY $_bestDate DESC, e.id DESC) AS rid '
          "$_joins ${_where(exclusion)} AND a.adminArea IS NOT NULL AND a.adminArea != '' WINDOW w AS (PARTITION BY a.countryCode, a.adminArea) ORDER BY cc ASC, nm ASC",
          variables: _variables(exclusion),
        )
        .get();
    return [
      for (final row in rows)
        StateSummaryRow(
          countryCode: row.data['cc'] as String?,
          adminArea: row.data['nm'] as String,
          count: (row.data['n'] as int?) ?? 0,
          sizeBytes: (row.data['s'] as int?) ?? 0,
          maxBestDate: (row.data['md'] as int?) ?? 0,
          recentId: row.data['rid'] as int,
        ),
    ];
  }

  Future<List<PlaceSummaryRow>> placeRows(SummaryExclusion exclusion) async {
    // Same `locality ?? adminArea` fallback as `AddressDetails.place`.
    const placeExpr = "COALESCE(NULLIF(a.locality, ''), a.adminArea)";
    final rows = await db
        .customSelect(
          'SELECT DISTINCT $placeExpr AS k, COUNT(*) OVER w AS n, COALESCE(SUM(e.sizeBytes) OVER w, 0) AS s, MAX($_bestDate) OVER w AS md, '
          'FIRST_VALUE(e.id) OVER (PARTITION BY $placeExpr ORDER BY $_bestDate DESC, e.id DESC) AS rid '
          '$_joins ${_where(exclusion)} AND $placeExpr IS NOT NULL WINDOW w AS (PARTITION BY $placeExpr) ORDER BY k ASC',
          variables: _variables(exclusion),
        )
        .get();
    return [
      for (final row in rows)
        PlaceSummaryRow(
          place: row.data['k'] as String,
          count: (row.data['n'] as int?) ?? 0,
          sizeBytes: (row.data['s'] as int?) ?? 0,
          maxBestDate: (row.data['md'] as int?) ?? 0,
          recentId: row.data['rid'] as int,
        ),
    ];
  }
}
