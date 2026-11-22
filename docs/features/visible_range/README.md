# Visible range

A saved filter expression applied to browsing: a base condition, AND-ed
restrictions, optional OR-ed supplements, and a casual lock that freezes what the
current session may change. One range belongs to the gallery; each wallpaper
group owns its own.

Status: **in progress**. The range model, the page, the lock and the wallpaper
integration are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- one gallery range and one range per wallpaper group, isolated by scope + owner;
- a base condition (mutually exclusive presets) plus restriction and supplement
  rules;
- two evaluation orders, inherited from the old scenario chips;
- applying candidates to the media set (append by default, replace for a rule);
- writing the current filters back over the rules a pin sheet targets;
- a lock with three permission presets, enforced on browsing and on mutations;
- the wallpaper page's browsing overlay, which joins the gallery range instead of
  replacing it;
- bundled default presets and rules, versioned and re-seeded on a bump.

Out of scope:

- a security boundary: the lock is casual protection inside Aves;
- narrowing the live wallpaper through the browsing overlay (it reads the saved
  group range directly);
- per-entry range membership outside the three collection paths.

## Version facts

| Fact | Value |
| --- | --- |
| Scopes | `gallery`, `wallpaper` |
| Orders | `intersectFirst`, `unionFirst` |
| Rule kinds | `restriction`, `supplement` |
| Lock presets | `readOnly`, `manageable`, `full` |
| Active styles | `section`, `compactChips`, `tiles` |
| Defaults bundle | `assets/visible_range_presets.json` |
| Defaults version | 4 (`VisibleRangeStore.defaultsVersion`) |
| Store keys | `gallery.rangeId`, `lock.preset`, `seeded`, `defaults.version`, `view.activeStyle` |
| Migrations | v5 tables, v6 descriptions, v9 base activation flag |
| Entry points | visible-range page, gallery chip, wallpaper group page |
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
| Browsing gate | `lib/features/visible_range/services/visible_range_gate.dart` |
| Locks | `lib/features/visible_range/services/visible_range_locks.dart` |
| Stats | `lib/features/visible_range/services/visible_range_candidate_stats.dart` |
| Views | `lib/features/visible_range/view/` |
| Tests | `test/features/visible_range/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
