# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli vacation get` / `vacation set <bodyText>` — read or enable the
## singleton VacationResponse. The /set response carries a NoCreate phantom
## in its create slot (no create rail). Note the asymmetry: the /set builder
## takes its update set BY VALUE, whereas Email/set takes Opt[...].

import jmap_client
import std/tables
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
  # The accumulating update-set constructor `.lift`s onto the one rail.
  let updSet = ?initVacationResponseUpdateSet(
    @[
      setIsEnabled(true),
      setSubject(Opt.some("Out of office")),
      setTextBody(Opt.some(body)),
    ]
  ).lift
  # update is passed BY VALUE here, unlike addEmailSet's Opt[...] update.
  let (b, handle) =
    ctx.client.newBuilder().addVacationResponseSet(ctx.mailAccount, updSet)
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(handle)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "VacationResponse/set: " & outcome.error.message
    ok(1)
  of mokValue:
    for id, res in outcome.value.updateResults: # NoCreate create slot; single update
      if res.isOk:
        echo "vacation response enabled"
      else:
        stderr.writeLine "vacation set failed for " & $id & ": " & res.error.message
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
