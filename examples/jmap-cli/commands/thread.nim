# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli thread show <threadId>` — Thread/get; print the thread's
## email ids. Thread is a SEALED type with NO public fields: `id` and
## `emailIds` are accessor funcs (diverging from Mailbox/Identity, whose
## fields are direct).

import jmap_client
import ./cli_session

proc run*(args: seq[string]): int =
  if args.len < 2 or args[0] != "show":
    stderr.writeLine "usage: jmap-cli thread show <threadId>"
    return 2
  let threadId = parseIdFromServer(args[1]).valueOr:
    stderr.writeLine "bad thread id: " & error.message
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (b, handle) = ctx.client.newBuilder().addThreadGet(
      ctx.mailAccount, ids = Opt.some(direct(@[threadId]))
    )
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Thread/get failed: " & error.message
    return 1
  if resp.list.len == 0:
    stderr.writeLine "thread not found"
    return 1
  for th in resp.list:
    # Thread is sealed: id and emailIds are accessor FUNCS, not fields.
    echo "thread ", $th.id, " has ", $th.emailIds.len, " emails:"
    for eid in th.emailIds:
      echo "  ", $eid
  return 0
