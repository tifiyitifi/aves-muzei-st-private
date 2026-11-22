# Fork logging

The fork's single logging facade: hierarchical channel gates over a swappable
sink, plus a per-area logger so a call site never repeats its channel key.

Status: **in progress**. The facade, the channel registry and the gated call
sites are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- one gate table keyed by hierarchical channel names (`log.<domain>[.<sub>]`);
- build-mode defaults plus a `--dart-define` escape hatch for any build;
- runtime control (`setEnabled`, `setLevel`, `only`) without a restart;
- a sink seam, so the backing transport can change without touching call sites;
- `AreaKeyLog`, one instance per module, so the key is declared once;
- mirroring warnings and errors to Logcat where the developer transport is not
  surfaced.

Out of scope:

- migrating upstream `debugPrint` call sites (a mass migration is not a feature);
- a log viewer UI, file sinks, upload or retention policy;
- per-record filtering by message content.

## Version facts

| Fact | Value |
| --- | --- |
| Levels | `verbose` 300, `debug` 500, `info` 800, `warning` 900, `error` 1000, `off` 2000 |
| Shared channels | `log.app`, `log.db`, `log.settings`, `log.media` |
| Debug default | every shared channel at `verbose` |
| Release default | nothing open; an opened channel surfaces `warning` and above |
| Override | `--dart-define=AVES_LOG_KEYS=a,b` |
| Sink default | `dart:developer` |
| Entry point | `Log.init(...)` from the composition root |
| Rule check | `scripts/check-logging-rules.ps1` |

## Reading order

1. `spec.md` — what a channel, a gate and a record are, and what must hold.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the gate resolution, the sink seam and the build defaults.
4. `decisions/` — why a hand-written facade, why prefixes, why `off` is a gate.
5. `testing.md` — how the host test drives the gate without a transport.

## Code map

| Layer | Path |
| --- | --- |
| Facade and area logger | `lib/features/logging/log.dart` |
| Levels | `lib/features/logging/log_level.dart` |
| Shared channels | `lib/features/logging/log_keys.dart` |
| Tests | `test/features/logging/log_test.dart` |

Feature-owned channels are declared in their own slice (for example
`log.collection_paging`, `log.wallpaper`) and passed to `Log.init` as
`debugChannels`; `LogKeys` holds only genuinely cross-cutting channels.

## Privacy note

The docs carry no real paths, titles or machine names. See `docs/README.md`.
