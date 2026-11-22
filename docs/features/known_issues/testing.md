# Known issues — testing

## Host coverage

`test/features/known_issues/known_issues_section_test.dart` pumps the widget tree
with the app's own localizations and asserts:

- the shared list has no blank and no repeated entry;
- the body About uses renders every entry;
- the page renders every entry, numbered;
- the number is a widget of its own, not a prefix of the entry text.

Both readers call the same `knownIssues(context)`, so the parity tests are the
guard against a reader keeping a private copy.

## Device checks

| Check | Steps |
| --- | --- |
| The page is reachable | Settings → Advanced → Known Issues; the list shows every entry |
| The page scrolls | Open it on a small phone; the last entry is reachable |
| TV layout | About on a TV build shows the same body under the section title |
| Localization | Switch the app language; the entries follow it, the numbers stay |

The Advanced → page link is asserted by the meta-settings catalog gate
(`page_registry_test.dart`), not here: the settings surface needs the full app
environment.

## Discipline

- An entry that stops being true is removed in the same change that lifts the
  limitation, with the `rules.md` row superseded rather than deleted.
- If a reader needs a subset (for example "first-run warnings"), filter the
  shared list; do not fork it.
- A test that needs every row must grow the viewport or scroll: the page is a
  lazy list.
