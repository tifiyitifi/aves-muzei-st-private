# 0002 — A probe failure keeps the old behaviour

Status: accepted.

## Context

A whole-folder rename moves everything the folder holds. Before offering it, a
probe compares the album's visible scope with the folder's total count. The probe
returns `null` when the scope cannot be compiled or the database cannot be read.

## Decision

A `null` probe allows the rename. The alternative is to refuse an action on a
guess, which blocks a real rename whenever a transient database error occurs.

## Consequences

- A transient probe failure does not block the user.
- In that window the folder rename may move rows the view did not show. The risk
  is accepted because the same database is needed for the row rewrite that
  follows, and a failure there now keeps the album state on the old folder
  (`0001`).
- The probe test `a database behind the view never reports unseen rows` pins the
  "no phantom unseen count" half of this contract.
