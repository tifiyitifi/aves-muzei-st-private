# 0001 — A transfer never sends the unedited copy

Status: accepted.

## Context

A session starts by copying the source into the staging folder under its
original name. The built-in editor can either overwrite that copy in place
(`saveOverride`) or write a second file (`saveCopy`). In the second case the
session holds both the unedited staged copy and the edited result.

The session page offered every output to the move/copy-back flow. On a name
conflict the user could choose "replace", and the platform then deleted the
target before writing the staged copy — so the original was replaced with the
unedited duplicate.

## Decision

A transfer acts on the edited outputs (`builtIn`, `external`, `unknown`) and
leaves the staged output out when any edited output exists. The staged copy is
only used when it is the session's sole output, which is the `saveOverride`
case.

## Consequences

- A `saveCopy` session moves only the edit the user made.
- A `saveOverride` session still transfers its single, edited copy.
- The unedited staged copy stays in the staging folder until the session is
  discarded; it is no longer a transfer candidate.
