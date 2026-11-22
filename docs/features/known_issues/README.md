# Known issues

The accepted limitation of the paged (non-full-load) engine and the wallpaper
family, surfaced where they matter: an About section and an Advanced settings
page over the same list.

Status: **in progress**. Both readers are on `avest-dev`; nothing is released
yet.

## Scope

In scope:

- one shared, ordered list of accepted limitations;
- the About section and the Advanced page render the same entries;
- a numbered entry whose number is a widget of its own, so RTL keeps it on the
  correct side;
- entries come from `lib/l10n/app_en.arb` (`aboutKnownIssues1` … `8`).

Out of scope:

- limitations that are planned for implementation (they belong in `tasks.md`, not
  in a page the user reads as "this is how it is");
- a bug tracker or a link to one;
- per-device or per-OEM conditions beyond the ones already accepted (the MIUI
  launcher-cache entry).

## Version facts

| Fact | Value |
| --- | --- |
| Entries | 8 (`aboutKnownIssues1` … `aboutKnownIssues8`) |
| Readers | About (mobile + TV) and the Advanced settings page |
| Route | `KnownIssuesPage.routeName` (`/settings/known_issues`) |
| Settings key | `MetaPageKeys.knownIssues` |
| Rule check | `scripts/check-known-issues-rules.ps1` |

## Reading order

1. `spec.md` — what the list is and what a reader must see.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the shared list, the numbered row and the two readers.
4. `decisions/` — why one list, why only accepted limitations, why Advanced.
5. `testing.md` — the widget test and the manual check.

## Code map

| Layer | Path |
| --- | --- |
| Shared list | `lib/features/known_issues/view/known_issues_section.dart` (`knownIssues`) |
| Section body | `KnownIssuesSection.buildBody` |
| Settings page | `lib/features/known_issues/view/known_issues_page.dart` |
| About wiring | `lib/widgets/about/about_mobile_page.dart`, `lib/widgets/about/about_tv_page.dart` |
| Settings wiring | `lib/features/meta_settings/data/catalog.dart`, `view/page_registry.dart` |
| Tests | `test/features/known_issues/` |

## Privacy note

The entries describe behaviour, never a file, album or account. See
`docs/README.md`.
