# Metadata settings engine — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## The gate

- WHEN no gate value is stored, THE SYSTEM SHALL treat the metadata engine as
  authoritative.
- WHEN the gate names the legacy engine, THE SYSTEM SHALL serve every read and
  write from the `SharedPreferences` store.
- WHEN a caller reads the settings key space, THE SYSTEM SHALL hide the gate key.
- WHEN a caller writes or removes the gate key through the settings store, THE
  SYSTEM SHALL ignore it and leave the stored gate untouched.
- WHEN the settings are cleared, THE SYSTEM SHALL re-assert the gate and report a
  failure to re-assert it.

## Initialization and switching

- WHEN the metadata store cannot be opened, THE SYSTEM SHALL serve the session
  from the legacy store and SHALL leave the gate unchanged.
- WHEN the user switches engines, THE SYSTEM SHALL initialize the incoming store
  before committing the switch.
- WHEN the gate cannot be persisted, THE SYSTEM SHALL abort the switch and keep
  the previous engine, its gate value and its active store.
- WHEN the switch commits, THE SYSTEM SHALL replay the keys whose values differ
  between the two stores, without marking them as recent edits.
- WHEN a replayed key differs, THE SYSTEM SHALL notify the change stream once for
  that key.

## Seeding

- WHEN the metadata engine becomes authoritative for the first time, THE SYSTEM
  SHALL copy the legacy store's user-visible settings that the metadata store
  does not have.
- WHEN the seed has completed once, THE SYSTEM SHALL not repeat it, even if the
  legacy store changes later.
- WHEN a seed attempt fails, THE SYSTEM SHALL leave the marker unwritten and
  SHALL resume on the next attempt without overwriting already copied keys.
- WHEN a legacy key is internal and transient, THE SYSTEM SHALL not copy it.
- WHEN a legacy key is internal but carries user-visible state, THE SYSTEM SHALL
  copy it.
- WHEN the seed copies keys, THE SYSTEM SHALL not copy the engine gate key.

## The metadata store

- WHEN a typed value is written and read back, THE SYSTEM SHALL return the same
  value and type.
- WHEN a stored value has a different type from the requested getter, THE SYSTEM
  SHALL return null instead of converting it.
- WHEN a write fails, THE SYSTEM SHALL re-sync the in-memory cache to the
  persisted state, without clobbering a later write to the same key.
- WHEN a caller awaits `flush`, THE SYSTEM SHALL wait for every pending write and
  SHALL NOT throw for a write that already failed.
- WHEN a stored type tag is unreadable, THE SYSTEM SHALL skip that row and log it.

## The catalog and the surface

- WHEN the catalog is validated, THE SYSTEM SHALL reject duplicate keys and a def
  that lacks the field its widget kind requires.
- WHEN a def targets an editor, a sub-page or an availability predicate, THE
  SYSTEM SHALL reject an unregistered key.
- WHEN the surface renders a category, THE SYSTEM SHALL render its defs in the
  declared sort order.
- WHEN a def is written through the generic path, THE SYSTEM SHALL validate the
  value and write it through the active store; an enum SHALL be persisted by
  member name.
- WHEN the value fails validation, THE SYSTEM SHALL discard it and leave the
  stored value unchanged.
- WHEN a sub-page def is searched, THE SYSTEM SHALL resolve the keys its page
  writes.
