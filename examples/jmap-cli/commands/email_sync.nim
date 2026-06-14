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
import jmap_client/convenience # opt-in; addEmailChangesToGet + getBoth(ChangesGetHandles)
import ./cli_session

proc currentEmailState(ctx: CliContext): Result[JmapState, string] =
  ## Email/changes diffs against the Email OBJECT state (GetResponse.state),
  ## not the query state, so the cursor is read from an Email/get. An empty
  ## ids list returns the state with no records to ship.
  let (b, h) = ctx.client.newBuilder().addEmailGet(
    ctx.mailAccount, ids = Opt.some(direct(newSeq[Id]()))
  )
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Email/get failed: " & error.message)
  ok(resp.state)

proc run*(args: seq[string]): int =
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  if args.len < 1:
    # No cursor supplied: report the current state for the caller to persist.
    let st = currentEmailState(ctx).valueOr:
      stderr.writeLine error
      return 1
    echo "current Email state: ", $st
    echo "re-run after a change:  jmap-cli email sync ", $st
    return 0

  # parseJmapState reconstructs the cursor from the CLI string — the same
  # state value a previous run printed. (Hub-public; even in the snapshot.)
  let sinceState = parseJmapState(args[0]).valueOr:
    stderr.writeLine "bad state: " & error.message
    return 2

  let (b, handles) =
    ctx.client.newBuilder().addEmailChangesToGet(ctx.mailAccount, sinceState)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let res = dr.getBoth(handles).valueOr: # ChangesGetResults[Email]{changes, get}
    stderr.writeLine "changes extraction failed: " & error.message
    return 1

  echo "created=", $res.changes.created.len, " updated=", $res.changes.updated.len,
    " destroyed=", $res.changes.destroyed.len, " hasMore=",
    $res.changes.hasMoreChanges
  echo "state: ", $res.changes.oldState, " -> ", $res.changes.newState
  # The *ChangesToGet convenience back-references ONLY /created into the get,
  # so res.get.list holds the created records' bodies; updated/destroyed are
  # reported as ids only (fetching their bodies needs the manual
  # addEmailChanges + addPartialEmailGet with rpUpdated).
  for e in res.get.list: # full Email records — created only
    let idStr = if e.id.isSome: $e.id.get() else: "?"
    echo "  created ", idStr, "  ", e.subject.valueOr("(no subject)")
  for id in res.changes.updated:
    echo "  updated ", $id
  for id in res.changes.destroyed:
    echo "  destroyed ", $id
  return 0
