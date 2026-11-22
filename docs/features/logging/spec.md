# Fork logging — requirements

## Records and channels

- WHEN a record is emitted on a closed channel, THE SYSTEM SHALL drop it.
- WHEN a record passes a channel's gate, THE SYSTEM SHALL forward its message,
  error and stack trace to the sink unchanged.
- WHEN a channel name has a dot-separated parent, THE SYSTEM SHALL apply the
  parent's gate to it unless it defines its own.
- WHEN two gates match one channel, THE SYSTEM SHALL use the longest matching
  prefix.
- WHEN the requested level is `off`, THE SYSTEM SHALL never treat it as a record.

## Control

- WHEN a channel is enabled at runtime, THE SYSTEM SHALL open it for every level
  in a debug build and for warnings and errors otherwise.
- WHEN a channel is disabled at runtime, THE SYSTEM SHALL close it again.
- WHEN a gate is set explicitly, THE SYSTEM SHALL apply exactly that level.
- WHEN `only` is called, THE SYSTEM SHALL close every channel but the listed
  ones.
- WHEN a caller asks whether a channel would emit a level, THE SYSTEM SHALL
  answer without emitting anything.

## Build modes and configuration

- WHEN the build is a debug build, THE SYSTEM SHALL open every shared channel at
  `verbose`.
- WHEN the build is a release build, THE SYSTEM SHALL open nothing by default.
- WHEN `AVES_LOG_KEYS` names channels, THE SYSTEM SHALL open them last, so an
  explicit list wins over the build default.
- WHEN a feature declares its own channel, THE SYSTEM SHALL let the composition
  root open it in a debug build without editing the shared registry.
- WHEN a release build emits a warning or an error, THE SYSTEM SHALL mirror it
  to Logcat, tagged with the channel.

## Call sites

- WHEN a module declares a logger, THE SYSTEM SHALL bind it to one channel so
  the key is named once.
- WHEN a feature adds a channel, THE SYSTEM SHALL declare it in that feature's
  slice; only cross-cutting channels belong in the shared registry.

## Non-goals

- WHEN an upstream module logs with `debugPrint`, THE SYSTEM SHALL keep it
  untouched; migrating it is not part of this feature.
