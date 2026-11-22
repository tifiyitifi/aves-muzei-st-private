# Visible range — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## A range is an expression

- WHEN a range has no active base and no active rules, THE SYSTEM SHALL restrict
  nothing.
- WHEN the order is `intersectFirst`, THE SYSTEM SHALL resolve the range as
  `(base AND restrictions) OR supplements`.
- WHEN the order is `unionFirst`, THE SYSTEM SHALL resolve the range as
  `(base OR supplements) AND restrictions`.
- WHEN the base is unrestricted, THE SYSTEM SHALL make the union step a no-op in
  both orders.
- WHEN a rule is switched off, THE SYSTEM SHALL ignore its filters.
- WHEN a rule holds several filters, THE SYSTEM SHALL AND them inside the rule.
- WHEN the range is unrestricted, THE SYSTEM SHALL report `isRestricted` false
  and apply no browsing filter.
- WHEN only supplements are active and the base is unrestricted, THE SYSTEM SHALL
  not restrict browsing.
- WHEN `isRestricted` is evaluated, THE SYSTEM SHALL consider only the base and
  the active restrictions.

## Candidates and the page

- WHEN the page lists the base section, THE SYSTEM SHALL start it with the
  unrestricted tile.
- WHEN a base is selected, THE SYSTEM SHALL show the unrestricted tile as an
  unselected option.
- WHEN a base preset was deleted, THE SYSTEM SHALL keep its filters as a selected
  custom tile.
- WHEN rules are listed, THE SYSTEM SHALL group them by kind and put defaults
  first.
- WHEN candidates share a filter set, THE SYSTEM SHALL share one stats key.
- WHEN a built-in candidate is named, THE SYSTEM SHALL use a localized key; a
  user rename SHALL stay plain text.
- WHEN the active section is built, THE SYSTEM SHALL repeat the base and the
  enabled rules, and SHALL omit an unrestricted base.
- WHEN a candidate has no explicit label, THE SYSTEM SHALL fall back to its filter
  labels.
- WHEN a candidate pair is reversed, THE SYSTEM SHALL keep the reverse semantics.
- WHEN no base is named, THE SYSTEM SHALL fall back to its filters in the summary.

## Persistence

- WHEN a range is saved, THE SYSTEM SHALL store the range and its rules as one
  aggregate.
- WHEN a range is read, THE SYSTEM SHALL qualify the read by scope and owner.
- WHEN a range is locked, THE SYSTEM SHALL persist its permissions; WHEN it is
  unlocked, THE SYSTEM SHALL drop the stale permissions.
- WHEN a rule set is replaced, THE SYSTEM SHALL replace the whole set.
- WHEN a range is deleted, THE SYSTEM SHALL delete its rules and applied targets.
- WHEN presets or view state are written, THE SYSTEM SHALL read the same values
  back after a restart.
- WHEN an applied target is recorded, THE SYSTEM SHALL keep it tied to its rule.
- WHEN a corrupt filter value is read, THE SYSTEM SHALL treat it as an empty set
  instead of crashing the browse.

## Applying and writing back

- WHEN candidates are applied, THE SYSTEM SHALL union their filters, deduplicated.
- WHEN the caller does not ask to replace, THE SYSTEM SHALL append the filters to
  the media set's current filters.
- WHEN candidates are applied, THE SYSTEM SHALL remember the applied targets.
- WHEN the current filters are written back, THE SYSTEM SHALL overwrite only the
  selected rule and base.
- WHEN a target is locked, THE SYSTEM SHALL skip it and count it, not fail the
  request.
- WHEN a pinned base is stored on a group, THE SYSTEM SHALL keep it on the range,
  not in the preset catalog.
- WHEN a rule is pinned, THE SYSTEM SHALL update the existing rule for the same
  conditions instead of stacking a duplicate.

## The lock

- WHEN the range is unlocked, THE SYSTEM SHALL allow every operation.
- WHEN the lock is read-only, THE SYSTEM SHALL withhold every edit but sharing.
- WHEN the lock is manageable, THE SYSTEM SHALL allow the operations it names.
- WHEN the range is unlocked, THE SYSTEM SHALL restore every operation.
- WHEN an action is mapped to the lock, THE SYSTEM SHALL use the permission the
  action needs.

## Browsing and the wallpaper overlay

- WHEN the gallery range is set or cleared, THE SYSTEM SHALL apply or clear it
  through the one gate every browsing path reads.
- WHEN a wallpaper page publishes its group, THE SYSTEM SHALL join that group
  scope to the gallery range instead of replacing it.
- WHEN the user suspends the gallery range on the wallpaper page, THE SYSTEM SHALL
  keep it a browsing choice and SHALL NOT write the saved range.
- WHEN the overlay value does not change, THE SYSTEM SHALL not notify listeners.
- WHEN the wallpaper page shows group 0, THE SYSTEM SHALL fall back to the gallery
  range alone.
- WHEN a newer page claims the overlay, THE SYSTEM SHALL let it publish and SHALL
  let the older page's release be a no-op.
- WHEN the trash filter is in the view, THE SYSTEM SHALL not apply a range to it.
- WHEN a summary query excludes the range, THE SYSTEM SHALL use the range's
  complement so counts agree with browsing.

## Bundled defaults

- WHEN the preset document is parsed, THE SYSTEM SHALL skip malformed entries.
- WHEN a preset names a standard directory, THE SYSTEM SHALL resolve it instead of
  hardcoding a path.
- WHEN a standard directory cannot be resolved, THE SYSTEM SHALL skip that
  candidate.
- WHEN the defaults version is newer than the stored one, THE SYSTEM SHALL
  re-seed built-ins, prune removed ones and keep user rules and state.
- WHEN defaults are seeded, THE SYSTEM SHALL switch restriction and supplement
  defaults off.
- WHEN a deleted default is restored, THE SYSTEM SHALL restore it switched off.
