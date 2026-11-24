# Visible range — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## Groups and conditions

A range is one **visibility group**. The gallery owns several mutually exclusive
groups plus one scope-wide outside pool; a wallpaper group owns exactly one
group. Inside a group, conditions play one of three roles:

- **source** — OR-ed with the other sources; each source ANDs its own filters.
- **restriction** — AND-ed on top of the sources.
- **supplement** — OR-ed back in.

- WHEN a range has no active condition, THE SYSTEM SHALL restrict nothing.
- WHEN the order is `intersectFirst`, THE SYSTEM SHALL resolve the group as
  `(sources AND restrictions) OR supplements`.
- WHEN the order is `unionFirst`, THE SYSTEM SHALL resolve the group as
  `(sources OR supplements) AND restrictions`.
- WHEN the sources are unrestricted, THE SYSTEM SHALL make the union step a no-op
  in both orders.
- WHEN a rule is switched off, THE SYSTEM SHALL ignore its filters.
- WHEN a rule holds several filters, THE SYSTEM SHALL AND them inside the rule.
- WHEN several sources are active, THE SYSTEM SHALL OR their rules.
- WHEN a group is unrestricted, THE SYSTEM SHALL report `isRestricted` false and
  apply no browsing filter.
- WHEN only supplements are active, THE SYSTEM SHALL not restrict browsing.
- WHEN `isRestricted` is evaluated, THE SYSTEM SHALL consider the active sources
  and restrictions only.

## Exclusive groups

- WHEN a group is made current, THE SYSTEM SHALL browse with it and write the
  pointer so a restart returns to it.
- WHEN a group is deleted and it was current, THE SYSTEM SHALL fall back to the
  first remaining group.
- WHEN the last group would be deleted, THE SYSTEM SHALL refuse and keep one.
- WHEN a lock is on, THE SYSTEM SHALL refuse to switch groups, create them or
  edit any condition until the PIN unlocks it.
- WHEN the gallery lock is on, THE SYSTEM SHALL freeze the whole gallery scope:
  every group, the outside pool and the current pointer.

### Group 0 is the 「Unrestricted」 sentinel

- WHEN group 0 is listed, THE SYSTEM SHALL label it 「Unrestricted」 and keep it
  first, empty and undeletable.
- WHEN a condition is written to group 0, THE SYSTEM SHALL refuse it.
- WHEN the save sheet lists targets, THE SYSTEM SHALL not offer group 0.
- WHEN a group is numbered, THE SYSTEM SHALL number group 0 as `0` and the data
  groups from `1`.

## The gallery page

- WHEN the page is built, THE SYSTEM SHALL list the groups, then the outside
  restrictions, then the outside supplements, then the current result.
- WHEN a group tile is built, THE SYSTEM SHALL show the group's browsed result
  (its own conditions joined with the outside pool) as its cover and count.
- WHEN a group tile is not the current group, THE SYSTEM SHALL dim it like a
  switched-off condition, so the exclusive choice reads at a glance.
- WHEN the outside pool is empty, THE SYSTEM SHALL still show both outside
  sections.
- WHEN a group is selected, THE SYSTEM SHALL switch the current group; a group
  tile SHALL NOT be applied to the media set like a condition.
- WHEN the overflow is opened with nothing selected, THE SYSTEM SHALL offer
  editing the current group; the offer SHALL be disabled while the current group
  is group 0.
- WHEN exactly one group tile is selected, THE SYSTEM SHALL offer editing that
  group; a condition or a multi-group selection SHALL offer no group edit.

## The group editor

- WHEN the user asks to edit a group, THE SYSTEM SHALL open a page that edits
  that group's base range, restrictions and supplements.
- WHEN the editor is open, THE SYSTEM SHALL keep the edits in a draft and SHALL
  ask to save or discard when the page closes.
- WHEN a condition is switched in the editor, THE SYSTEM SHALL toggle its
  `active` state and keep the filters.
- WHEN 「Unrestricted」 is chosen in the editor, THE SYSTEM SHALL switch the
  group's sources off and keep their filters, so a parked source can be switched
  back on instead of being lost.
- WHEN the group is saved, THE SYSTEM SHALL replace the group and its conditions
  together.
- WHEN the edited group is group 0, THE SYSTEM SHALL not offer the editor.

## The outside pool (gallery)

- WHEN a group resolves, THE SYSTEM SHALL apply the outside pool last:
  `(group AND outsideRestrictions) OR outsideSupplements`.
- WHEN the group is unrestricted, THE SYSTEM SHALL let an outside supplement
  restrict nothing.
- WHEN only an outside restriction is active, THE SYSTEM SHALL narrow with it.
- WHEN the outside pool is edited, THE SYSTEM SHALL accept restrictions and
  supplements only; it SHALL have no source role.
- WHEN the gallery is locked, THE SYSTEM SHALL freeze the outside pool too.

## Saving into a range

The user-facing action is 「save to visible range」, distinct from the filter
pin: one confirmation writes the media set's filters into the chosen targets
immediately (it is not a draft).

- WHEN a media set is pinned to a group, THE SYSTEM SHALL split it: a source-only
  union becomes one source per member, every other positive source stays one
  conjunctive source, and the rest becomes restrictions.
- WHEN a filter is reversed or mixes a source with a narrowing filter, THE SYSTEM
  SHALL keep it a restriction.
- WHEN the user forces a role, THE SYSTEM SHALL override the automatic split and
  SHALL NOT promise equivalence with the media set.
- WHEN a group has no conditions yet, THE SYSTEM SHALL enable the first pinned
  conditions; otherwise it SHALL park them, unless the pin overrides the mode.
- WHEN the same conditions are pinned again, THE SYSTEM SHALL update the existing
  condition and keep its state.
- WHEN the write mode is replace, THE SYSTEM SHALL drop the conditions already in
  the group.
- WHEN the target is the outside pool, THE SYSTEM SHALL write one condition per
  filter in that pool's role.
- WHEN the target is the gallery and it is locked, THE SYSTEM SHALL skip every
  gallery target and count it.
- WHEN the user asks to remember the injection mode, THE SYSTEM SHALL read it
  back; otherwise the sheet SHALL start from `auto`.
- WHEN the remember option is cleared, THE SYSTEM SHALL drop the stored mode so
  the next open starts from `auto`.
- WHEN the save sheet is opened, THE SYSTEM SHALL name the injection mode as the
  only remembered option; the role, append/replace and write-back selection
  SHALL start fresh every time.
- WHEN the automatic split is chosen, THE SYSTEM SHALL select it directly; a
  custom role SHALL be picked from a menu on every tap and SHALL apply to this
  save only.
- WHEN a group already holds conditions, THE SYSTEM SHALL offer append and
  replace as two named choices.
- WHEN the save sheet is opened, THE SYSTEM SHALL start with no group selected.
- WHEN the sheet lists targets, THE SYSTEM SHALL name the gallery section
  「Normal groups」 apart from 「Wallpaper groups」 and SHALL name the scope-wide
  pool 「Outside groups」.
- WHEN the write-back rules are folded away, THE SYSTEM SHALL name every selected
  write location outside the collapsible section: the checked groups first, then
  the checked rules, and no others.
- WHEN a group or a rule is ticked, THE SYSTEM SHALL update that list in the same
  frame it updates the checkbox or the tile, without re-reading the store.
- WHEN nothing is selected at all, THE SYSTEM SHALL say that nothing will be
  written and SHALL keep the save action disabled.

## Candidates and the page

- WHEN the page lists the base section, THE SYSTEM SHALL start it with the
  unrestricted tile.
- WHEN a source exists, THE SYSTEM SHALL show the unrestricted tile as an
  unselected option and the source as a selected one.
- WHEN several sources exist, THE SYSTEM SHALL list them as parallel tiles.
- WHEN rules are listed, THE SYSTEM SHALL group them by kind and put defaults
  first.
- WHEN candidates share a filter set, THE SYSTEM SHALL share one stats key.
- WHEN a built-in candidate is named, THE SYSTEM SHALL use a localized key; a
  user rename SHALL stay plain text.
- WHEN the active section is built, THE SYSTEM SHALL repeat the sources and the
  enabled rules, and SHALL omit an unrestricted source.
- WHEN a candidate has no explicit label, THE SYSTEM SHALL fall back to its filter
  labels.
- WHEN a candidate pair is reversed, THE SYSTEM SHALL keep the reverse semantics.
- WHEN no source is named, THE SYSTEM SHALL fall back to its filters in the
  summary.

## Persistence

- WHEN a range is saved, THE SYSTEM SHALL store the range and its rules as one
  aggregate.
- WHEN groups are listed, THE SYSTEM SHALL return only groups in display order;
  the outside pool SHALL NOT be listed as a browsable group.
- WHEN a range is locked, THE SYSTEM SHALL persist its permissions; WHEN it is
  unlocked, THE SYSTEM SHALL drop the stale permissions.
- WHEN a rule set is replaced, THE SYSTEM SHALL replace the whole set.
- WHEN a range is deleted, THE SYSTEM SHALL delete its rules and applied targets.
- WHEN presets or view state are written, THE SYSTEM SHALL read the same values
  back after a restart.
- WHEN a v18 database upgrades, THE SYSTEM SHALL turn each base into a source
  rule, move the old gallery rules to the outside pool, make the old preset group
  current, and keep the legacy base columns one release for a rollback.
- WHEN an applied target is recorded, THE SYSTEM SHALL keep it tied to its rule.
- WHEN a corrupt filter value is read, THE SYSTEM SHALL treat it as an empty set
  instead of crashing the browse.

## Applying and writing back

- WHEN candidates are applied, THE SYSTEM SHALL union their filters, deduplicated.
- WHEN the caller does not ask to replace, THE SYSTEM SHALL append the filters to
  the media set's current filters.
- WHEN candidates are applied, THE SYSTEM SHALL remember the applied targets.
- WHEN the current filters are written back, THE SYSTEM SHALL overwrite only the
  selected rule and the range's source.
- WHEN a target is locked, THE SYSTEM SHALL skip it and count it, not fail the
  request.
- WHEN a source is pinned to a group, THE SYSTEM SHALL keep it on the range, not
  in the preset catalog.
- WHEN a condition is pinned, THE SYSTEM SHALL update the existing condition for
  the same conditions instead of stacking a duplicate.

## The lock

- WHEN the range is unlocked, THE SYSTEM SHALL allow every operation.
- WHEN the lock is read-only, THE SYSTEM SHALL withhold every edit but sharing.
- WHEN the lock is manageable, THE SYSTEM SHALL allow the operations it names.
- WHEN the range is unlocked, THE SYSTEM SHALL restore every operation.
- WHEN an action is mapped to the lock, THE SYSTEM SHALL use the permission the
  action needs.
- WHEN the gallery lock is on, THE SYSTEM SHALL freeze every gallery group, the
  outside pool and the current pointer, and SHALL require the PIN to unlock.
- WHEN the wallpaper group lock is on, THE SYSTEM SHALL hide the other groups,
  refuse switching and freeze edits to every group, the locked one included.

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

## The bar and the two fork pages

- WHEN the wallpaper page and the group editor are both open, THE SYSTEM SHALL
  derive both bar entries on the configured side and order them by open time:
  the first opened sits nearest the visible-range entry.
- WHEN the editor is opened in the shared mode, THE SYSTEM SHALL replace the
  visible-range entry in place, like the wallpaper page.
- WHEN the editor is opened in a separate mode, THE SYSTEM SHALL push it over
  the page it was opened from and SHALL resolve its bar entry to the editor
  page: an unregistered fork route leaves the entry dead.
- WHEN the editor's entry is tapped while the editor is on top, THE SYSTEM SHALL
  keep the single page instead of stacking another one.
- WHEN the editor's session is closed, THE SYSTEM SHALL render the range page.
- WHEN the group editor's page is restored after a process death, THE SYSTEM
  SHALL land on the visible-range page: the editor's group is session state.
