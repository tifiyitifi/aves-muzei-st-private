# 0008 — The base header names sources, not exclusivity

Date: 2026-11-24

Refines `0007`.

## Context

`0007` made the base a union of independently switched sources. The Chinese
section header still read 「基础范围（互斥唯一）」, and the about copy still said
「基础范围（互斥）」 / "Base range (exclusive)": exclusivity belongs to the
*groups*, not to a group's sources. The same label is shared by the wallpaper
pool, the group editor and the gallery page's outside sections, so one ARB key
kept the contradiction visible in three places.

The header count disagreed too. The group editor showed `1/2` of its sources
(and `0/0` for an empty rule section), while the wallpaper page showed no count
at all; the outside sections on the gallery page computed their own count. A
「None」 tile is a placeholder, but `0/0` treated it as a condition.

## Decision

- The base section header is a role name: "base sources" / 「基础来源」. No
  parenthetical exclusivity note in any locale, and the about copy describes the
  base as an OR union of sources.
- One pure helper, `visibleRangeSectionCountText`, supplies the header count on
  the group editor, the wallpaper pool and the gallery page's outside sections.
  It reports `active/total` of real conditions, excludes the unrestricted choice
  (「Unrestricted」 and 「All images」 share one id), and returns an empty string
  when the section has no condition.
- The wallpaper base header now shows the sources marked on the lamped surface
  over all of the pool's sources, so the two editing surfaces read the same way.
- Role labels elsewhere (move to base range, save as base range, write-back
  lines) keep their existing wording; this decision only names the section
  header and the about copy.

## Alternatives rejected

- **Drop only 「（互斥唯一）」 and keep 「基础范围」.** It removes the error but
  still reads as one range, while the section lists several OR-ed sources.
- **Keep separate count rules per page.** The same condition would show `1/2`
  in the editor and nothing on the wallpaper page, which is what made the two
  entry points look inconsistent.
- **Count 「All images」 in the base denominator.** It is the absence of a
  source, not one of them; counting it would make `0/2` mean "one source, off".

## Consequences

- The English test asserts `base sources`, and a Chinese-locale test asserts
  「基础来源」 with no parenthetical note, so the old wording cannot return.
- An empty section shows a bare header above its 「None」 tile.
- The helper is shared from `visible_range`, imported by both fork slices; the
  role labels and the stored model do not change.
