# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email sync [<sinceState>]` — incremental sync, the path a real
## mail client lives on. With no argument it reports the current Email state
## so it can be persisted; given a prior state it drives the `syncEmails`
## one-shot (Email/changes -> two back-referenced Email/gets) and prints the
## created/updated/destroyed delta plus the fetched records.
##
## Both findings this command filed are RESOLVED. The bootstrap no longer
## issues an empty-ids Email/get to read a cursor out of a payload response —
## `getEmailState` is the named accessor for it. And the delta is no longer
## created-records-only: `syncEmails` back-references BOTH `/created` and
## `/updated`, so the case a mail client actually cares about (a message that
## was read, flagged or moved) arrives with its record, not as a bare id.
##
## Notably positive: a JmapState round-trips through `parseJmapState`, so a
## consumer CAN persist a sync cursor across process restarts — the state is
## not trapped inside a live response.

import jmap_client
import ./cli_session

func idLabel(e: Email): string =
  ## `Email.id` is `Opt[Id]` on the read model; every record printed here came
  ## from a server get, so the absent case is unreachable in practice.
  for id in e.id:
    return $id
  "?"

proc reportCurrentState(ctx: CliContext): JmapResult[int] =
  ## Email/changes diffs against the Email OBJECT state, not the query state.
  ## `getEmailState` is the accessor for it — the bootstrap no longer borrows a
  ## payload response's `state` field via an empty-ids get.
  let state = ?ctx.client.getEmailState(ctx.mailAccount)
  echo "current Email state: ", $state
  echo "re-run after a change:  jmap-cli email sync ", $state
  ok(0)

proc syncSince(ctx: CliContext, sinceArg: string): JmapResult[int] =
  # parseJmapState reconstructs the cursor from the CLI string — the same state
  # value a previous run printed — and `.lift`s any rejection onto the rail.
  let sinceState = ?parseJmapState(sinceArg).lift

  # One call for the whole delta: the changes call plus both record fetches,
  # each outcome collapsed onto the rail, so there is no per-method `case` here.
  # The trade the bench records: the hand-wired path treated a failed body fetch
  # as non-fatal and still printed the counts and the cursor, whereas the folded
  # path is fail-fast, so any one method error now costs the cursor line too.
  let sync = ?ctx.client.syncEmails(ctx.mailAccount, sinceState)

  let ch = sync.changes
  echo "created=",
    $ch.created.len,
    " updated=",
    $ch.updated.len,
    " destroyed=",
    $ch.destroyed.len,
    " hasMore=",
    $ch.hasMoreChanges
  echo "state: ", $ch.oldState, " -> ", $ch.newState
  # A record created AND then updated since the cursor legitimately appears in
  # both lists (RFC 8620 §5.2); a real client dedupes by id, a bench prints what
  # the server said.
  for e in sync.created.list:
    echo "  created ", idLabel(e), "  ", e.subject.valueOr("(no subject)")
  for e in sync.updated.list:
    echo "  updated ", idLabel(e), "  ", e.subject.valueOr("(no subject)")
  # Nothing is left to fetch for a destroyed record, so the ids are the delta.
  for id in ch.destroyed:
    echo "  destroyed ", $id
  ok(0)

proc syncImpl(args: seq[string]): JmapResult[int] =
  let ctx = ?connect()
  if args.len < 1:
    # No cursor supplied: report the current state for the caller to persist.
    reportCurrentState(ctx)
  else:
    syncSince(ctx, args[0])

proc run*(args: seq[string]): int =
  syncImpl(args).valueOr:
    stderr.writeLine error.message
    return 1
