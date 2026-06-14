# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email move <emailId> <mailboxId>` — replace an email's mailbox
## membership via the moveToMailbox convenience EmailUpdate (full replace).
## Same triple-sealing chain as `email flag`; the repetition is the finding.

import jmap_client
import std/[tables, strutils, sequtils]
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 2:
    stderr.writeLine "usage: jmap-cli email move <emailId> <mailboxId>"
    return 2
  let emailId = parseIdFromServer(args[0]).valueOr:
    stderr.writeLine "bad email id: " & error.message
    return 2
  let mailboxId = parseIdFromServer(args[1]).valueOr:
    stderr.writeLine "bad mailbox id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1

  let updSet = initEmailUpdateSet(@[moveToMailbox(mailboxId)]).valueOr:
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
  for id, res in setResp.updateResults:
    if res.isOk:
      echo "moved ", $id
    else:
      stderr.writeLine "move failed for " & $id & ": " & res.error.message
  return 0
