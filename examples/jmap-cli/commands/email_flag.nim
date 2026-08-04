# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email flag <emailId>` — mark an email $seen via Email/set.
## The EmailUpdate DSL -> EmailUpdateSet -> NonEmptyEmailUpdates triple-sealing
## chain this command used to document is RESOLVED: `markEmailsRead` folds the
## two seal steps, the build/dispatch lifecycle and the Email/set outcome into
## one call, so the write reads as account + ids + verb and a method error
## arrives through `?`.
##
## The per-item `Table[Id, Result[Opt[PartialEmail], SetError]]` update results
## stay data on the ok branch, and the hand-written `isOk` walk over them is
## gone: the `updated` / `updateFailures` projection iterators read each rail
## directly. The `std/tables` dependency survives that swap, though — see the
## import comment below.

import jmap_client
# Residual container leak: the projection iterators are generic, so Nim resolves
# their Table `pairs` at THIS instantiation site — a hub-only consumer still
# needs std/tables in scope to read any /set response.
from std/tables import pairs
import ./cli_session

proc flagEmail(emailIdArg: string): JmapResult[int] =
  let emailId = ?parseIdFromServer(emailIdArg).lift
  let ctx = ?connect()

  # markRead()'s $seen op, sealed across the ids, dispatched and collapsed in
  # one call — no update set, no keyed batch, no `case outcome.kind` here.
  let resp = ?ctx.client.markEmailsRead(ctx.mailAccount, @[emailId])

  # A SetError is data within a successful method — reported per id, never fatal
  # to the whole command. The success arm's Opt[PartialEmail] server echo is
  # unused for a flag, which is exactly what the iterator split makes cheap.
  for id, serverEcho in resp.updated:
    echo "flagged ", $id, " $seen"
  for id, error in resp.updateFailures:
    stderr.writeLine "flag failed for " & $id & ": " & error.message
  ok(0)

proc run*(args: seq[string]): int =
  if args.len < 1:
    stderr.writeLine "usage: jmap-cli email flag <emailId>"
    return 2
  flagEmail(args[0]).valueOr:
    stderr.writeLine error.message
    return 1
