# 0002 — Seeding is one-shot but resumable

Status: accepted.

## Context

v2 became the default engine while existing installs already had their settings
in v1. Copying nothing would reset every preference on upgrade. Copying on every
init would resurrect values the user deliberately cleared, and would overwrite
changes they made in v2.

## Decision

`MetaSettingsSeeder` runs when v2 becomes authoritative and the `appMeta` marker
is absent. It copies only keys v2 does not already hold, and writes the marker
only after a complete pass.

## Consequences

- A first upgrade keeps the user's settings.
- An interrupted seed resumes; a retry cannot overwrite a value changed in v2 in
  the meantime.
- A deliberate v2 reset stays reset, because the marker survives it.
- The two stores remain independent after the seed, which keeps the v1 rollback
  lossless.
