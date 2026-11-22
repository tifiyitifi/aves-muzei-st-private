# Known issues — requirements

## The list

- WHEN the list is built, THE SYSTEM SHALL contain only limitations the project
  accepts for good.
- WHEN a limitation is lifted, THE SYSTEM SHALL remove its entry.
- WHEN a limitation is planned for implementation, THE SYSTEM SHALL keep it out
  of the list.
- WHEN the list is built, THE SYSTEM SHALL contain no blank and no repeated
  entry.
- WHEN an entry is displayed, THE SYSTEM SHALL render it from the localized list,
  never from a hardcoded string.
- WHEN the list order changes, THE SYSTEM SHALL keep a limitation's relative place
  stable, because the numbers readers quote depend on it.

## The About section

- WHEN the About page renders, THE SYSTEM SHALL show the numbered list built from
  the shared source.
- WHEN the app runs in TV layout, THE SYSTEM SHALL show the same body as the
  mobile About page.

## The settings page

- WHEN the user opens Known Issues under Advanced, THE SYSTEM SHALL show every
  entry of the shared list.
- WHEN an entry is rendered, THE SYSTEM SHALL draw its number as a widget of its
  own, separate from the entry text.
- WHEN the list is longer than the viewport, THE SYSTEM SHALL scroll it.

## Non-goals

- WHEN a limitation is a bug the project intends to fix, THE SYSTEM SHALL not
  present it as a known issue.
- WHEN a limitation depends on one OEM build, THE SYSTEM SHALL describe the
  condition without naming a private file or path.
