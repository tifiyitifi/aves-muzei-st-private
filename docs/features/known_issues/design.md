# Known issues — design

## One list, two readers

```text
app_en.arb ──► knownIssues(context) ──► KnownIssuesSection.buildBody ──► About (mobile/TV)
                                    └──► KnownIssuesPage (ListView)   ──► Advanced settings
```

`knownIssues(BuildContext)` returns the ordered `List<String>` and is the only
place an entry is added or removed. `KnownIssuesSection` keeps the About chrome
(section title, spacing) around `buildBody`, which both About pages call;
`KnownIssuesPage` repeats the rows inside a `ListView.builder`, so a long list
scrolls instead of overflowing.

The section's doc comment states the editorial rule the code cannot enforce: an
entry is an accepted limitation, not planned work. Burst/RAW stacking and the
calendar/mosaic layouts are named in the comment as examples of *not* here,
because they are on the roadmap.

## The numbered row

`KnownIssuesSection.knownIssueRow(context, index, issue)` returns a `Row` of
`Text('${index + 1}.')`, a spacer and `Expanded(Text(issue))`. The number is a
widget of its own rather than a prefix of the string: under RTL a concatenated
`2. <paragraph>` would place the number at the paragraph's visual start, which is
the wrong side for a list marker. `Expanded` gives the paragraph the remaining
width so it wraps.

## Placement

- **About** describes what the app is and what it cannot do; the list belongs
  there first.
- **Advanced** sits next to the collection engine selector and the batch
  expectations, where a user who changed those settings looks for the trade-off
  they just accepted. The page uses the shared body so the two cannot drift.

## Anti-patterns

- Rendering the entries from a private list in either reader: the About section
  and the page would diverge on the first edit.
- Concatenating the number into the text: breaks RTL.
- Adding a roadmap item: the page is a promise about today, not a plan.
- Linking a limitation's entry to a task id or a file path: the docs are
  published, the paths are not.
