# Known issues — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-known-issues-rules.ps1` resolves every `F:`
token.

## The list

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| KNI-1 | One entry per limitation | WHEN the list is built, THE SYSTEM SHALL hold no blank or repeated entry | a copy-pasted entry documents the same limitation twice and shifts every number after it | `F:known_issues_section_test#the shared list holds no blank or repeated entry` |
| KNI-2 | Accepted for good | WHEN the list is edited, THE SYSTEM SHALL add only a limitation the project accepts | a planned fix would turn the page into a roadmap | `-:an editorial rule about the content; the code cannot falsify it (see design.md)` |
| KNI-3 | Lifted limitation | WHEN a limitation is lifted, THE SYSTEM SHALL remove its entry | the page must not outlive the behaviour it describes | `-:the edit that lifts the limitation owns the removal; no runtime behaviour to assert` |
| KNI-4 | Localized text | WHEN an entry is displayed, THE SYSTEM SHALL come from the ARB key set | a hardcoded string would never be translated | `-:a missing key is a compile error, so the host has nothing to falsify` |
| KNI-5 | Stable order | WHEN entries are reordered, THE SYSTEM SHALL keep readers' quotes meaningful | the numbered list is referenced by number | `-:the order is data, asserted only by reading the list; the numbers are checked by KNI-6` |

## About

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| KNI-6 | About body | WHEN the About body is built, THE SYSTEM SHALL render every entry of the shared list | About is the first place a user meets the limitations | `F:known_issues_section_test#the body shared with About renders every entry` |
| KNI-7 | TV body | WHEN the app runs in TV layout, THE SYSTEM SHALL reuse the same body | two lists would drift | `-:the TV page composes the same builder; only a device shows the TV layout (see testing.md)` |

## Settings page

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| KNI-8 | Full list | WHEN the settings page renders, THE SYSTEM SHALL show every entry of the shared list | the page exists to be complete | `F:known_issues_section_test#the known-issues page renders every entry, numbered` |
| KNI-9 | Numbering | WHEN an entry is rendered, THE SYSTEM SHALL draw its number as a widget of its own | a concatenated number moves to the wrong side under RTL | `F:known_issues_section_test#an entry keeps its number out of its own text` |
| KNI-10 | Reachability | WHEN the user opens Advanced, THE SYSTEM SHALL offer the Known Issues entry, which opens the page | the page is useless if it is unreachable | `-:needs the full settings surface; the catalog row and the page registry entry are checked by the meta-settings catalog gate` |
| KNI-11 | Scrolling | WHEN the list exceeds the viewport, THE SYSTEM SHALL scroll instead of overflowing | the entries are long paragraphs | `-:layout behaviour; the page is a ListView, and the widget test grows the viewport to build every row` |
