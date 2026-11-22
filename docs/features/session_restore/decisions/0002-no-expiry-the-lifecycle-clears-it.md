# No expiry: the lifecycle decides when a snapshot is stale

Status: accepted.

## Context

The snapshot exists to survive a process death while paused. A timestamp plus a
TTL is the usual answer, but the events that make a snapshot wrong are not "too
old" — they are "the user left" or "the task is gone".

## Decision

The snapshot carries no timestamp and expires on no clock. It is cleared on
back-out from the main page and when the lifecycle reaches `detached`, and
otherwise overwritten by the next main-mode pause. A plain launch restores it
regardless of age.

## Why

- A TTL would need an injected clock and would still be wrong for an app that is
  killed ten seconds after pausing.
- Back-out and task-swipe are exact signals; time is a proxy.
- One less field means one less validation branch and one less test.

## Consequences

- A snapshot written days ago is restored if the user never backs out and never
  swipes the task, which is exactly "the last page they were on in this task".
- An intent launch skips reading the snapshot but does not clear it; the next
  plain launch still reopens the older main-mode page.

## Alternatives rejected

- A 24-hour TTL: arbitrary, and it would drop a restore the user expects.
- Clearing after a successful restore: it would break a second plain launch of
  the same task, which currently reopens the page.
