# 0003 — The locks are casual and per kind

Status: accepted.

## Context

The visible range and the wallpaper group can both be "locked". They are
unrelated pages and unrelated actions: one freezes which photos the gallery
shows, the other stops someone leaving the wallpaper group that was set. A
single lock would make one page's protection depend on the other's.

The app already has a vault for privacy. A second security boundary would be
misleading, and a PIN in the settings store would be exported with the settings.

## Decision

Two independent locks, each with its own 4-digit PIN:

- the visible range keeps its `locked` column and the service only verifies the
  PIN to unlock or temporarily ignore it;
- the group switch keeps a flag plus the group id in `appMeta`.

PINs live in the platform's encrypted preferences (the vault store), are never
part of settings import/export, and default to `1234` until written. There is no
forgot-PIN flow: clearing app data is the reset.

## Consequences

- Locking is not a security boundary; any app with the same access, `adb` or root
  can bypass it. The UI says so.
- A lock survives leaving the page, the app and a process restart.
- A wrong PIN keeps the lock; changing a PIN requires the current one.
- The two locks cannot be unlocked through each other.
