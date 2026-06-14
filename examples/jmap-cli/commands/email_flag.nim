# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email flag <emailId>` — mark an email $seen via Email/set.
## Shows the EmailUpdate DSL -> EmailUpdateSet -> NonEmptyEmailUpdates
## triple-sealing chain (both seal steps ride an accumulating
## seq[ValidationError] rail) and the
## Table[Id, Result[Opt[PartialEmail], SetError]] update-result read-back.

import jmap_client
import std/[tables, strutils, sequtils]
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email flag <emailId>"
    return 2
  let emailId = parseIdFromServer(args[0]).valueOr:
    stderr.writeLine "bad email id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  # DSL -> per-email update set -> keyed batch. markRead() sets $seen and is
  # total; the two seal steps each accumulate a seq[ValidationError].
  let updSet = initEmailUpdateSet(@[markRead()]).valueOr:
    stderr.writeLine "invalid update set: " & error.mapIt(it.message).join("; ")
    return 1
  let updates = parseNonEmptyEmailUpdates(@[(emailId, updSet)]).valueOr:
    stderr.writeLine "invalid update batch: " & error.mapIt(it.message).join("; ")
    return 1

  let (b, handle) =
    ctx.client.newBuilder().addEmailSet(ctx.mailAccount, update = Opt.some(updates))
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let setResp = dr.get(handle).valueOr:
    stderr.writeLine "Email/set failed: " & error.message
    return 1

  # Per-item rail: Result[Opt[PartialEmail], SetError] (the inner Opt is
  # usually none for a flag); guard with isOk to read the SetError safely.
  for id, res in setResp.updateResults:
    if res.isOk:
      echo "flagged ", $id, " $seen"
    else:
      stderr.writeLine "flag failed for " & $id & ": " & res.error.message
  return 0
