# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email flag <emailId>` — mark an email $seen via Email/set.
## Shows the EmailUpdate DSL -> EmailUpdateSet -> NonEmptyEmailUpdates
## triple-sealing chain. Both seal steps ride the accumulating
## ``NonEmptySeq[ValidationError]`` rail, so each composes onto the one
## JmapError rail with a single ``.lift`` — the former
## ``mapIt(it.message).join`` flattening is gone. The per-item
## ``Table[Id, Result[Opt[PartialEmail], SetError]]`` update results stay data
## on the ok branch.

import jmap_client
import std/tables
import ./cli_session

proc flagEmail(emailIdArg: string): JmapResult[int] =
  let emailId = ?parseIdFromServer(emailIdArg).lift
  let ctx = ?connect()

  # DSL -> per-email update set -> keyed batch. markRead() sets $seen and is
  # total; the two seal steps each accumulate violations and `.lift` onto the rail.
  let updSet = ?initEmailUpdateSet(@[markRead()]).lift
  let updates = ?parseNonEmptyEmailUpdates(@[(emailId, updSet)]).lift

  let (b, handle) =
    ctx.client.newBuilder().addEmailSet(ctx.mailAccount, update = Opt.some(updates))
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(handle)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Email/set: " & outcome.error.message
    ok(1)
  of mokValue:
    # Per-item rail: Result[Opt[PartialEmail], SetError] (the inner Opt is
    # usually none for a flag). A SetError is data within a successful method —
    # reported, never fatal to the whole command.
    for id, res in outcome.value.updateResults:
      if res.isOk:
        echo "flagged ", $id, " $seen"
      else:
        stderr.writeLine "flag failed for " & $id & ": " & res.error.message
    ok(0)

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email flag <emailId>"
    return 2
  flagEmail(args[0]).valueOr:
    stderr.writeLine error.message
    return 1
