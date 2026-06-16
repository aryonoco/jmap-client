# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli thread show <threadId>` — Thread/get; print the thread's
## email ids. `id` and `emailIds` are direct public fields, uniform with
## Mailbox/Identity. `emailIds` is a `NonEmptyIdSeq` whose non-empty
## invariant lives in the type, yet it reads like a plain seq (`.len`,
## iteration) with no unwrap.

import jmap_client
import ./cli_session

proc showThread(threadIdArg: string): JmapResult[int] =
  # The id is server-sourced (lenient parser); folding it onto the rail with one
  # `.lift` keeps the whole body on the single JmapError rail.
  let threadId = ?parseIdFromServer(threadIdArg).lift
  let ctx = ?connect()
  # getThreads folds the get lifecycle and collapses the single Thread/get
  # outcome onto the rail; explicit ids still wrap as Opt.some(direct(@[id])).
  let resp =
    ?ctx.client.getThreads(ctx.mailAccount, ids = Opt.some(direct(@[threadId])))
  if resp.list.len == 0:
    stderr.writeLine "thread not found"
    return ok(1)
  for th in resp.list:
    # id and emailIds are direct public fields; emailIds (a NonEmptyIdSeq)
    # answers `.len` and iterates directly — no .toSeq needed to print it.
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
