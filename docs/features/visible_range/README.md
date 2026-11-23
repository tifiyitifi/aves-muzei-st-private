# Visible range

Visibility groups applied to browsing. A group holds OR-ed **sources**, AND-ed
**restrictions** and OR-ed **supplements**; the gallery owns several mutually
exclusive groups plus one shared outside pool, and each wallpaper group owns one
group whose conditions are marked per surface. A casual lock freezes the whole
scope the current session may change.

Status: **in progress**. The range model, the page, the lock and the wallpaper
integration are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- several mutually exclusive gallery groups plus one shared outside pool, and one
  group per wallpaper group, isolated by scope + owner;
- a gallery page that lists the groups, the outside restrictions, the outside
  supplements and the current result; group 0 is the 「Unrestricted」 sentinel;
- a group editor that edits the group's base range, restrictions and supplements
  on a draft, with each condition switched in or out;
- source (OR), restriction (AND) and supplement (OR) conditions inside a group;
- two evaluation orders, inherited from the old scenario chips;
- saving a media set into a group (automatic split, optional forced role) or into
  the outside pool, with an inject-and-enable / inject-only policy;
- applying candidates to the media set (append by default, replace for a rule);
- writing the current filters back over the rules a save sheet targets;
- a lock with three permission presets that freezes a whole scope: the gallery's
  groups and outside pool, or the wallpaper group set;
- the wallpaper page's browsing overlay, which joins the gallery group instead of
  replacing it;
- bundled default groups and outside rules, versioned and re-seeded on a bump.

Out of scope:

- a security boundary: the lock is casual protection inside Aves;
- narrowing the live wallpaper through the browsing overlay (it reads the saved
  group range directly);
- per-entry range membership outside the three collection paths.

## Version facts

| Fact | Value |
| --- | --- |
| Scopes | `gallery`, `wallpaper` |
| Range kinds | `group`, `outside` |
| Orders | `intersectFirst`, `unionFirst` |
| Rule kinds | `source`, `restriction`, `supplement` |
| Injection modes | `auto`, `enable`, `park` |
| Pin write modes | `append`, `replace` |
| Lock presets | `readOnly`, `manageable`, `full` |
| Active styles | `section`, `compactChips`, `tiles` |
| Defaults bundle | `assets/visible_range_presets.json` |
| Defaults version | 4 (`VisibleRangeStore.defaultsVersion`) |
| Store keys | `gallery.current`, `lock.preset`, `seeded`, `defaults.version`, `view.activeStyle`, `pin.injection.mode`, `pin.injection.remembered` |
| Migrations | v5 tables, v6 descriptions, v9 base activation flag, v19 visibility groups, v20 gallery reset |
| Entry points | visible-range page, group editor, gallery chip, save sheet, wallpaper group page |
| Rule check | `scripts/check-visible-range-rules.ps1` |

## Reading order

1. `spec.md` — what a range is and what it must do.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — how the model, the store, the gate and the lock fit.
4. `decisions/` — why a range is a filter expression, why the wallpaper scope
   joins instead of replacing, and why defaults are re-seeded.
5. `testing.md` — gates, fixtures and the manual checks.

## Code map

| Layer | Path |
| --- | --- |
| Model | `lib/features/visible_range/model/` |
| Bundled defaults | `lib/features/visible_range/data/default_presets.dart`, `assets/visible_range_presets.json` |
| Store | `lib/features/visible_range/db/` |
| Controller | `lib/features/visible_range/services/visible_range_controller.dart` |
| Editor session / nav | `lib/features/visible_range/services/visible_range_editor_session.dart`, `view/visible_range_group_open.dart` |
| Browsing gate | `lib/features/visible_range/services/visible_range_gate.dart` |
| Locks | `lib/features/visible_range/services/visible_range_locks.dart` |
| Stats | `lib/features/visible_range/services/visible_range_candidate_stats.dart` |
| Page layout | `lib/features/visible_range/view/visible_range_page_sections.dart` |
| Views | `lib/features/visible_range/view/`, `visible_range_group_editor_page.dart` |
| Tests | `test/features/visible_range/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
