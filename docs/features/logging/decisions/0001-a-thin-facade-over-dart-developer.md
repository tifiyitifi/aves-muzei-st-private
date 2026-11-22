# The facade is hand-written over `dart:developer`

Status: accepted.

## Context

The fork needed per-area gating: a release build must be silent unless asked, a
debug build must show everything, and a developer must be able to turn one area
on without a rebuild. Upstream logs with `debugPrint`, which has none of that.

## Decision

Implement the gates in the fork (`lib/features/logging/log.dart`) and forward
records to `dart:developer` through a function-typed sink. No logging package is
added.

## Why

- The behaviour needed is a prefix-gated table over five levels; a package would
  add a dependency, its own configuration and its own sink abstraction for the
  same thing.
- `dart:developer` is already DevTools' transport, so severity and channel names
  appear without configuration.
- The sink seam keeps the transport replaceable: a future file sink assigns one
  function.

## Consequences

- The release mirror to Logcat is our code (`kDebugMode` branch + `debugPrint`
  with the channel tag), not a package feature.
- A feature that wants its own channel declares it in its slice and passes it to
  `Log.init` as `debugChannels`.

## Alternatives rejected

- `debugPrint` everywhere: not gated, and stripped in release.
- `package:logging`: correct but heavier, and it still needs the sink we already
  need.
