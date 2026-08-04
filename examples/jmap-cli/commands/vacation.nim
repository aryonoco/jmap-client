# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli vacation get` / `vacation set <bodyText>` — read or enable the
## singleton VacationResponse. The /set response still carries a NoCreate
## phantom in its create slot (no create rail), but the builder's by-value
## update set — the asymmetry against Email/set's Opt[...] — is now folded
## inside `setVacationResponse`, so neither convention surfaces at the call
## site and the singleton id stays the library's concern.

import jmap_client
import ./cli_session

proc doGet(ctx: CliContext): JmapResult[int] =
  # getVacationResponse folds the get lifecycle and collapses the singleton
  # VacationResponse/get outcome onto the rail (the singleton takes no ids).
  let resp = ?ctx.client.getVacationResponse(ctx.mailAccount)
  if resp.list.len == 0:
    echo "no vacation response configured"
    return ok(0)
  # The get path has clean plain-Opt fields (the set ECHO path is FieldEcho).
  let vr = resp.list[0]
  echo "enabled: ", vr.isEnabled
  for s in vr.subject:
    echo "subject: ", s
  for t in vr.textBody:
    echo "text:    ", t
  ok(0)

proc doSet(ctx: CliContext, body: string): JmapResult[int] =
  # setVacationResponse takes the update DSL ops directly: the accumulating
  # update-set seal, the singleton id and the set lifecycle all fold into the
  # one call, so a method error arrives through `?`.
  let resp = ?ctx.client.setVacationResponse(
    ctx.mailAccount,
    @[
      setIsEnabled(true),
      setSubject(Opt.some("Out of office")),
      setTextBody(Opt.some(body)),
    ],
  )
  # One singleton, so at most one of these loops yields — the update rails read
  # through the projection iterators, not the keyed updateResults table.
  for id, serverEcho in resp.updated:
    echo "vacation response enabled"
  for id, error in resp.updateFailures:
    stderr.writeLine "vacation set failed for " & $id & ": " & error.message
  ok(0)

proc vacationImpl(args: seq[string]): JmapResult[int] =
  let ctx = ?connect()
  case args[0]
  of "get":
    doGet(ctx)
  of "set":
    doSet(ctx, args[1])
  else:
    ok(2) # unreachable — verb validated in run*; case over string needs an else

proc run*(args: seq[string]): int =
  # Validate the subcommand BEFORE any network call (mirrors thread.nim), so a
  # bogus verb is rejected without a wasted connect/fetchSession round-trip.
  if args.len < 1 or args[0] notin ["get", "set"]:
    stderr.writeLine "usage: jmap-cli vacation get | vacation set <bodyText>"
    return 2
  if args[0] == "set" and args.len < 2:
    stderr.writeLine "usage: jmap-cli vacation set <bodyText>"
    return 2
  vacationImpl(args).valueOr:
    stderr.writeLine error.message
    return 1
