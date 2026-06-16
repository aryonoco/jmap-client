# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email sync [<sinceState>]` — incremental sync, the path a real
## mail client lives on. With no argument it reports the current Email state
## so it can be persisted; given a prior state it drives the opt-in
## convenience combinator `addEmailChangesToGet` (Email/changes -> Email/get
## back-reference) and prints the created/updated/destroyed delta plus the
## fetched records.
##
## Notably positive: a JmapState round-trips through `parseJmapState`, so a
## consumer CAN persist a sync cursor across process restarts — the state is
## not trapped inside a live response.

import jmap_client
import ./cli_session

proc reportCurrentState(ctx: CliContext): JmapResult[int] =
  ## Email/changes diffs against the Email OBJECT state (GetResponse.state),
  ## not the query state, so the cursor is read from an Email/get. The getEmails
  ## one-shot folds that get and collapses its outcome onto the rail; an empty
  ## ids list returns the state with no records to ship.
  let resp =
    ?ctx.client.getEmails(ctx.mailAccount, ids = Opt.some(direct(newSeq[Id]())))
  echo "current Email state: ", $resp.state
  echo "re-run after a change:  jmap-cli email sync ", $resp.state
  ok(0)

proc syncSince(ctx: CliContext, sinceArg: string): JmapResult[int] =
  # parseJmapState reconstructs the cursor from the CLI string — the same state
  # value a previous run printed — and `.lift`s any rejection onto the rail.
  let sinceState = ?parseJmapState(sinceArg).lift

  let (b, handles) =
    ctx.client.newBuilder().addEmailChangesToGet(ctx.mailAccount, sinceState)
  let dr = ?ctx.client.send(b.freeze())
  # ChangesGetResults[Email]{changes, get}: the rail carries only dispatch
  # faults; each side is a MethodOutcome handled per branch.
  let res = ?dr.getBoth(handles)
  case res.changes.kind
  of mokMethodError:
    stderr.writeLine "Email/changes: " & res.changes.error.message
    ok(1)
  of mokValue:
    let ch = res.changes.value
    echo "created=",
      $ch.created.len,
      " updated=",
      $ch.updated.len,
      " destroyed=",
      $ch.destroyed.len,
      " hasMore=",
      $ch.hasMoreChanges
    echo "state: ", $ch.oldState, " -> ", $ch.newState
    # The *ChangesToGet convenience back-references ONLY /created into the get,
    # so the get side holds the created records' bodies; updated/destroyed are
    # reported as ids only. A method error on the body fetch is non-fatal — the
    # primary changes delta still stands.
    case res.get.kind
    of mokMethodError:
      stderr.writeLine "Email/get (created bodies): " & res.get.error.message
    of mokValue:
      for e in res.get.value.list: # full Email records — created only
        let idStr =
          if e.id.isSome:
            $e.id.get()
          else:
            "?"
        echo "  created ", idStr, "  ", e.subject.valueOr("(no subject)")
    for id in ch.updated:
      echo "  updated ", $id
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
