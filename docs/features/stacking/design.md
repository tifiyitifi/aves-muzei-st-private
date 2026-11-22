# Stacking — design

## The policy

`tileIds(rows, hasBurstKey:)` is a pure function over
`StackRow = ({int id, String? path, String? mimeType})`. It returns
`Map<int, int?>`: every row id mapped to the tile it hides behind, or `null` when
it shows itself.

Two passes, in order:

1. **Burst pass** — group the rows that carry a `stackKey`; the first by natural
   base name is the tile, the rest hide behind it.
2. **Developed/RAW pass** — over the survivors, group by `(directory, baseName)`;
   when a group holds a developed image and a RAW, hide the RAW behind the
   developed image.

A RAW can therefore only pair with a developed image that survived the burst
pass; a mixed burst cannot hide its own tile. The base name drops only the last
extension, so `a.tar.gz` groups as `a.tar`; a dotfile keeps its name.

## The representative

`compareNames` reuses the file-name comparison (`compareAsciiUpperCaseNatural`,
then `compareAsciiUpperCase` on the extension). It deliberately does **not** use
`AvesEntrySort.compareByName`, which reads `bestTitle`: a title on one frame is
exotic, and metadata arriving later would move the tile.

The comparison is ASCII-uppercase and natural (numbers by value), so it is
deterministic across devices and independent of the locale. A non-ASCII name still
sorts by code unit; that is the legacy behaviour and the reason a burst of
accented names can tile an arbitrary frame.

## Group identity is persisted

The policy computes the tile, but the *paged view* must hide a member with one
indexed predicate, and SQLite cannot reverse-derive a base name. The write path
therefore materializes `baseName`, `stackKey` and `stackTileId` (schema v4).
`stackTileId IS NULL` means "shows itself"; a member points at a row whose own
value is `NULL`, so the set of tiles is finite and the member query stays
indexed.

Because the tile is settled over the whole group in the database, a filter cannot
move it. The view compensates with "hide a member only while its tile is in the
same scope" (registered as `LEN-28`), so a filtered-out tile returns its members
instead of deleting them.

The write path owns the index: inserts, updates, moves and deletes re-settle the
affected groups (`QRY-6`, `QRY-8`), and the v4 migration backfills existing rows
(`MIG-3`).

## Boundaries

- **Paged presentation** belongs to `collection_paging`: hiding, the calendar's
  day rows, and the after-window attachment of members.
- **Persistence** belongs to `drift_db`: settling, re-homing and the backfill.
- The policy has no IO and reads no settings; the caller supplies the patterns
  (write path) or a `hasBurstKey` flag (read path).

## Anti-patterns

- Deriving the tile from the current filtered view: a rating filter would move
  which frame the user sees.
- Comparing `bestTitle`: metadata arriving later would re-tile a burst.
- Hiding a member whose tile is outside the predicate: the file would disappear
  with nothing to open.
- Writing `stackTileId` from a single row's insert: a group decision needs the
  whole group.
- Grouping a day row and a stack at once: the calendar owns its grouping.
