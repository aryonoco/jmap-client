# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test configuration. Reads JMAP_TEST_<SERVER>_* env vars
## emitted by .devcontainer/scripts/seed-<server>.sh and returns every
## configured target. Each ``t*_live.nim`` wraps its body in
## ``forEachLiveTarget(target):`` so a single testament invocation
## iterates over both servers in deterministic order (Stalwart, James).
##
## Categories A–E are documented in
## ``docs/plan/11-integration-testing-K-james.md``.

{.push raises: [].}

import std/os
import results

type LiveTargetKind* = enum
  ## Typed identifier of the JMAP server under test. The string value
  ## backs ``$kind`` for capture filenames and assertion-message
  ## prefixing, while the enum kind itself enables exhaustive ``case``
  ## branching in Categories C/D/E (no ``else: doAssert false`` fallback
  ## required — adding a third server is a compile error at every branch
  ## site).
  ltkStalwart = "stalwart"
  ltkJames = "james"

type LiveTestTarget* = object
  ## A configured JMAP server. ``kind`` flows into capture filenames
  ## (via its backing string) and into typed ``case`` branches in
  ## Categories C/D. ``sessionUrl`` is the JMAP session-document
  ## endpoint; ``authScheme`` is ``Basic`` for both Stalwart and James.
  kind*: LiveTargetKind
  sessionUrl*: string
  authScheme*: string
  aliceToken*: string
  bobToken*: string

proc loadTarget(kind: LiveTargetKind, prefix: string): Opt[LiveTestTarget] =
  ## Reads the four ``<prefix>_SESSION_URL`` / ``_AUTH_SCHEME`` /
  ## ``_ALICE_TOKEN`` / ``_BOB_TOKEN`` env vars and returns a populated
  ## ``LiveTestTarget``. Returns ``Opt.none`` when any of the four are
  ## absent so the caller can compose multiple loaders without raising.
  let su = getEnv(prefix & "_SESSION_URL")
  let sc = getEnv(prefix & "_AUTH_SCHEME")
  let at = getEnv(prefix & "_ALICE_TOKEN")
  let bt = getEnv(prefix & "_BOB_TOKEN")
  if su.len == 0 or sc.len == 0 or at.len == 0 or bt.len == 0:
    return Opt.none(LiveTestTarget)
  Opt.some(
    LiveTestTarget(
      kind: kind, sessionUrl: su, authScheme: sc, aliceToken: at, bobToken: bt
    )
  )

proc loadLiveTestTargets*(): Result[seq[LiveTestTarget], string] =
  ## Returns Stalwart, then James. Errs only when no target is
  ## configured. Live tests guard their bodies on ``.isOk`` so files
  ## join testament's megatest cleanly when no env vars are set.
  var targets: seq[LiveTestTarget] = @[]
  for tgt in loadTarget(ltkStalwart, "JMAP_TEST_STALWART"):
    targets.add(tgt)
  for tgt in loadTarget(ltkJames, "JMAP_TEST_JAMES"):
    targets.add(tgt)
  if targets.len == 0:
    return err(
      "no live targets configured — set JMAP_TEST_STALWART_* and/or JMAP_TEST_JAMES_*"
    )
  ok(targets)

template forEachLiveTarget*(targetIdent, body: untyped) =
  ## Iteration template every live test wraps its body in. Inner
  ## ``block:`` per target so let-bindings stay scoped.
  let liveTargetsRes = loadLiveTestTargets()
  if liveTargetsRes.isOk:
    for targetIdent in liveTargetsRes.get():
      block:
        body
