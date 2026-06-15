# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli thread show <threadId>` — Thread/get; print the thread's
## email ids. Thread is a SEALED type with NO public fields: `id` and
## `emailIds` are accessor funcs (diverging from Mailbox/Identity, whose
## fields are direct).

import jmap_client
import ./cli_session

proc showThread(threadIdArg: string): JmapResult[int] =
  # The id is server-sourced (lenient parser); folding it onto the rail with one
  # `.lift` keeps the whole body on the single JmapError rail.
  let threadId = ?parseIdFromServer(threadIdArg).lift
  let ctx = ?connect()
  let (b, handle) = ctx.client.newBuilder().addThreadGet(
      ctx.mailAccount, ids = Opt.some(direct(@[threadId]))
    )
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(handle)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Thread/get: " & outcome.error.message
    ok(1)
  of mokValue:
    if outcome.value.list.len == 0:
      stderr.writeLine "thread not found"
      return ok(1)
    for th in outcome.value.list:
      # Thread is sealed: id and emailIds are accessor FUNCS, not fields.
      echo "thread ", $th.id, " has ", $th.emailIds.len, " emails:"
      for eid in th.emailIds:
        echo "  ", $eid
    ok(0)

proc run*(args: seq[string]): int =
  if args.len < 2 or args[0] != "show":
    stderr.writeLine "usage: jmap-cli thread show <threadId>"
    return 2
  showThread(args[1]).valueOr:
    stderr.writeLine error.message
    return 1
