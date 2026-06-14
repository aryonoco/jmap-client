# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli vacation get` / `vacation set <bodyText>` — read or enable the
## singleton VacationResponse. The /set response carries a NoCreate phantom
## in its create slot (no create rail). Note the asymmetry: the /set builder
## takes its update set BY VALUE, whereas Email/set takes Opt[...].

import jmap_client
import std/[tables, strutils, sequtils]
import ./cli_session

proc doGet(ctx: CliContext): int =
  let (b, handle) = ctx.client.newBuilder().addVacationResponseGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "VacationResponse/get failed: " & error.message
    return 1
  if resp.list.len == 0:
    echo "no vacation response configured"
    return 0
  # The get path has clean plain-Opt fields (the set ECHO path is FieldEcho).
  let vr = resp.list[0]
  echo "enabled: ", vr.isEnabled
  for s in vr.subject:
    echo "subject: ", s
  for t in vr.textBody:
    echo "text:    ", t
  return 0

proc doSet(ctx: CliContext, body: string): int =
  let updSet = initVacationResponseUpdateSet(
      @[setIsEnabled(true), setSubject(Opt.some("Out of office")), setTextBody(Opt.some(body))]
    ).valueOr:
    stderr.writeLine "invalid vacation update: " & error.mapIt(it.message).join("; ")
    return 1
  # update is passed BY VALUE here, unlike addEmailSet's Opt[...] update.
  let (b, handle) = ctx.client.newBuilder().addVacationResponseSet(ctx.mailAccount, updSet)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "VacationResponse/set failed: " & error.message
    return 1
  for id, res in resp.updateResults: # NoCreate create slot; single update entry
    if res.isOk:
      echo "vacation response enabled"
    else:
      stderr.writeLine "vacation set failed for " & $id & ": " & res.error.message
  return 0

proc run*(args: seq[string]): int =
  # Validate the subcommand BEFORE any network call (mirrors thread.nim), so a
  # bogus verb is rejected without a wasted connect/fetchSession round-trip.
  if args.len < 1 or args[0] notin ["get", "set"]:
    stderr.writeLine "usage: jmap-cli vacation get | vacation set <bodyText>"
    return 2
  if args[0] == "set" and args.len < 2:
    stderr.writeLine "usage: jmap-cli vacation set <bodyText>"
    return 2
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  case args[0]
  of "get":
    doGet(ctx)
  of "set":
    doSet(ctx, args[1])
  else:
    2 # unreachable — verb validated above; case over string needs an else
