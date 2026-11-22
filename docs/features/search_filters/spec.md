# Search filters (assist) — requirements

## The relative window

- WHEN a token is an amount followed by `h` or `d`, THE SYSTEM SHALL parse it into
  a positive span, ignoring case and spaces.
- WHEN a token is null, empty, unit-only, amount-only, zero, negative, unknown or
  fractional, THE SYSTEM SHALL reject it.
- WHEN a span is serialized, THE SYSTEM SHALL emit `<amount><h|d>` and parse back
  to the same value.
- WHEN a relative filter is constructed, THE SYSTEM SHALL anchor its cutoff at the
  current time minus the span, once.
- WHEN a relative filter tests an entry, THE SYSTEM SHALL accept entries whose
  best date is at or after the cutoff.
- WHEN an entry has no best date, THE SYSTEM SHALL not match it in the window.
- WHEN a relative filter is reversed, THE SYSTEM SHALL match the entries the
  positive test rejects, undated entries included.
- WHEN a relative filter is reversed, THE SYSTEM SHALL keep the window's cutoff.
- WHEN two relative filters are compared, THE SYSTEM SHALL compare span and
  reversal only, not the anchor.
- WHEN a relative filter round-trips through JSON, THE SYSTEM SHALL persist its
  span and reversal and re-anchor on restore.
- WHEN a stored span is corrupt, THE SYSTEM SHALL drop the filter.

## The numeric range

- WHEN a range is tested, THE SYSTEM SHALL treat both bounds as inclusive and an
  absent bound as open.
- WHEN the entry has no value for the field, THE SYSTEM SHALL not match it; the
  reversed range SHALL match it.
- WHEN the field is a taken date, THE SYSTEM SHALL read the best date.
- WHEN the field is the size, THE SYSTEM SHALL read the file size.
- WHEN the field is the width or height, THE SYSTEM SHALL read the displayed size,
  including the rotation swap.
- WHEN the field is a content id, THE SYSTEM SHALL match only entries that carry
  one.
- WHEN a range round-trips through JSON, THE SYSTEM SHALL preserve field, bounds
  and reversal, omitting absent bounds.
- WHEN the stored field is unknown, THE SYSTEM SHALL drop the filter.

## Composition

- WHEN the assist is empty, THE SYSTEM SHALL build no filter.
- WHEN a path condition is included or excluded, THE SYSTEM SHALL build the
  corresponding `PathFilter`.
- WHEN date, size and content-id ranges are set, THE SYSTEM SHALL build one
  `RangeAssistFilter` per field.
- WHEN a dimension range is set, THE SYSTEM SHALL build a width filter and a
  height filter.
- WHEN a dimension range is empty, THE SYSTEM SHALL add nothing.
- WHEN a recent window is set, THE SYSTEM SHALL build a relative filter with that
  span.
- WHEN one extension is set, THE SYSTEM SHALL build the single `EXT=` query; WHEN
  several are set, THE SYSTEM SHALL OR them.
- WHEN extensions are stored, THE SYSTEM SHALL lowercase them and strip the
  leading dot.
- WHEN a condition is removed or the "other" conditions are cleared, THE SYSTEM
  SHALL keep the remaining conditions and the path.

## SQL parity

- WHEN SQL and the in-memory predicate run over the same rows, THE SYSTEM SHALL
  select the same ids for every assist field.
- WHEN a range or a window is reversed, THE SYSTEM SHALL keep the rows without the
  field in SQL exactly as the Dart test does.
- WHEN an assist set compiles, THE SYSTEM SHALL AND the fragments and require only
  the joins each field needs.

## Lists and sheets

- WHEN the sheet shows a match count, THE SYSTEM SHALL treat it as advisory and
  omit it rather than block.
- WHEN the user picks a date preset or a custom range, THE SYSTEM SHALL compute a
  local-day window and add no new filter type.
- WHEN the size unit changes, THE SYSTEM SHALL convert both fields so the byte
  value is unchanged.
- WHEN a size bound is reloaded, THE SYSTEM SHALL show it in the largest unit
  that represents it exactly, and SHALL NOT round a positive bound to zero.
- WHEN a size field is blank, unparsable or not positive, THE SYSTEM SHALL treat
  it as no bound.
- WHEN the unit menu renders, THE SYSTEM SHALL use the localized unit label.
- WHEN the lower bound exceeds the upper, THE SYSTEM SHALL refuse to apply it.
- WHEN the user applies the assist, THE SYSTEM SHALL union the built filters with
  the typed query and add them to the collection.
