# 0007 — The base is an OR union, and the editor is a bar destination

Date: 2026-11-24

Refines `0005` and `0006`.

## Context

`0005` gave every group three roles, and `0006` moved the gallery group's roles to
their own draft page. Two gaps remained in the way users actually build a group:

- On the wallpaper group page, tapping any base tile called `setBaseSurface`,
  which switched **every** source on that surface at once. Several sources could
  be stored but not kept on together, so the base behaved like one exclusive
  choice. That contradicts `grouped_wallpaper/spec.md` FR-13 ("Home/Lock mark each
  condition independently").
- The gallery editor's 「Unrestricted」 tile deleted the group's source rules. A
  user who only wanted to browse everything for a moment lost the filters they
  had just pinned.
- Opening the editor in the default separate navigation mode threw `unknown
  route`: the fork route was never registered in `AvesNavItem`'s page builder,
  so the entry existed but did nothing.

## Decision

- **The base range is a union of visible sources.** Each source is an OR member
  and can be switched on or off on its own, on both the gallery editor and the
  wallpaper pool. Several albums or paths stay several sources.
- **「Unrestricted」 parks, it does not delete.** It switches the sources off and
  keeps their filters, exactly like a rule that is switched off (`MOD-2`); the
  tile is active when no source is *active*.
- **`All images` clears a surface's marks, not the pool.** The conditions stay
  available for the other surface or a later re-mark.
- **The group editor is a bottom-bar destination.** In the shared mode it
  replaces the visible-range entry in place; otherwise it has its own entry and
  is pushed over the page it was opened from, so closing it returns there and a
  process death restores the range page. `AvesNavItem` must resolve the entry to
  the editor page. The entry on the page itself is not stacked twice.

Role reassignment stays available: the save sheet's forced role and the rule
actions' move-to-base / restriction / supplement let a user put any filter in any
of the three parts.

## Consequences

- A group can be built from several sources and narrowed by restrictions without
  a second pin round-trip.
- A pinned source survives an 「Unrestricted」 visit.
- Every new fork route needs an `AvesNavItem` page-builder case; the route is
  built eagerly, so a missing case fails at tap time, not at compile time.

## Alternatives rejected

- **Keep the base as one on/off unit and split only at display time.** The
  stored set would still be switched as a whole, so the display would promise an
  independence the model does not have.
- **Delete the sources on 「Unrestricted」.** It loses the user's pin for a
  transient browsing state; parking is reversible at no storage cost.
- **Replace the stack when opening the editor.** It would drop the range page
  the editor was opened from, so back and a process death would leave the
  feature instead of returning to the page it belongs to.
