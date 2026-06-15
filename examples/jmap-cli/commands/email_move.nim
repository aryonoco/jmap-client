# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email move <emailId> <mailboxId>` — replace an email's mailbox
## membership via the moveToMailbox convenience EmailUpdate (full replace).
## Same triple-sealing chain as `email flag`; the repetition is the finding.
## Both seal steps `.lift` their accumulating violations onto the one rail.

import jmap_client
import std/tables
import ./cli_session

proc moveEmail(emailIdArg, mailboxIdArg: string): JmapResult[int] =
  let emailId = ?parseIdFromServer(emailIdArg).lift
  let mailboxId = ?parseIdFromServer(mailboxIdArg).lift
  let ctx = ?connect()

  let updSet = ?initEmailUpdateSet(@[moveToMailbox(mailboxId)]).lift
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
    for id, res in outcome.value.updateResults:
      if res.isOk:
        echo "moved ", $id
      else:
        stderr.writeLine "move failed for " & $id & ": " & res.error.message
    ok(0)

proc run*(args: seq[string]): int =
  if args.len < 2:
    stderr.writeLine "usage: jmap-cli email move <emailId> <mailboxId>"
    return 2
  moveEmail(args[0], args[1]).valueOr:
    stderr.writeLine error.message
    return 1
