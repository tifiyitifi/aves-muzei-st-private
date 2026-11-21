# 0007 — The album destination is a stored album

Date: 2026-11-21

## Context

The view page's menu offered 「Open in gallery」, which already opened the app's
viewer. The label therefore named a destination the action never reached, and the
menu had no way to reach the album the photo is filed under while the group
destination dropped the user at the top of the group's list.

The group's conditions are path filters: they describe a folder tree the wallpaper
may draw from. That is not the same thing as the photo's album, which is the one
shelf the photo is filed under.

## Decision

The view hands the photo to three destinations, and names them for what they do:

- **Open in viewer** — the app's viewer on the photo.
- **Open in album** — the photo's `StoredAlbumFilter`, never a `PathFilter`, with
  the photo revealed in the list.
- **View whole group** — the group's `wallpaperMediaSetFilter` on the surface the
  page describes, also with the photo revealed.

The reveal is `CollectionPage`'s existing `highlightTest`, so the list scrolls to
the photo and marks it. Both collection destinations are pushed over the view, so
back returns to the photo; the whole-group action used to push the same page
without a locate target.

The pad's stored action is named `openInGallery`; that name is the persisted
identity, so it stays and only its label changes. 「Open in album」 is appended to
the enum as `openInAlbum`, which leaves every saved pad untouched.

## Alternatives rejected

- **Reuse the group's resolved range for the album.** It is a tree, not the album,
  and it changes when the wallpaper changes.
- **Use a `PathFilter` for the album.** It includes subdirectories and reads as a
  folder, which is exactly the confusion this record removes.
- **Open the album grid and let the user pick the album again.** The user is
  already looking at the photo; the destination is its album.
- **Leave the whole-group action without a locate target.** The user came from
  one photo of a possibly long list, so the top of the list is not where they
  left.

## Consequences

- `groupedWallpaperAlbumTarget` and `groupedWallpaperWholeGroupTarget` build the
  destinations and are covered by `grouped_wallpaper_view_actions_test.dart`.
- `groupedWallpaperViewOpenInGallery` is renamed to
  `groupedWallpaperViewOpenInViewer`, and
  `groupedWallpaperViewOpenInAlbum` is added.
- `rules.md` DEST-1…DEST-3, `spec.md` FR-10 and the slice README hold the
  behaviour.
