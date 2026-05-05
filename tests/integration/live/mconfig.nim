# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test configuration. Reads JMAP_TEST_<SERVER>_* env vars
## emitted by .devcontainer/scripts/seed-<server>.sh and returns every
## configured target. Each ``t*_live.nim`` wraps its body in
## ``forEachLiveTarget(target):`` so a single testament invocation
## iterates over the configured targets in enum order.
##
## Categorisation post-Phase-L is documented in
## ``docs/plan/12-integration-testing-L-cyrus.md`` (37 Cat-A + 31 Cat-B
## + 5 Cat-D + 0 Cat-E = 73). Cat-B sites use
## ``assertSuccessOrTypedError`` (mlive.nim) to assert client behaviour
## uniformly across every target's RFC-conformant response shape.

{.push raises: [].}

import std/os
import results

type LiveTargetKind* = enum
  ## Typed identifier of the JMAP server under test. The string value
  ## backs ``$kind`` for capture filenames and assertion-message
  ## prefixing, while the enum kind itself enables exhaustive ``case``
  ## branching in Cat-D verification-path sites (no ``else: doAssert
  ## false`` fallback required — adding a fourth server is a compile
  ## error at every branch site).
  ltkStalwart = "stalwart"
  ltkJames = "james"
  ltkCyrus = "cyrus"

type LiveTestTarget* = object
  ## A configured JMAP server. ``kind`` flows into capture filenames
  ## (via its backing string) and into typed ``case`` branches in
  ## Cat-D verification-path sites. ``sessionUrl`` is the JMAP
  ## session-document endpoint; ``authScheme`` is ``Basic`` for every
  ## currently-configured target.
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
  ## Returns the configured targets in enum order (Stalwart, James,
  ## Cyrus). Errs only when no target is configured. Live tests guard
  ## their bodies on ``.isOk`` so files join testament's megatest
  ## cleanly when no env vars are set.
  var targets: seq[LiveTestTarget] = @[]
  for tgt in loadTarget(ltkStalwart, "JMAP_TEST_STALWART"):
    targets.add(tgt)
  for tgt in loadTarget(ltkJames, "JMAP_TEST_JAMES"):
    targets.add(tgt)
  for tgt in loadTarget(ltkCyrus, "JMAP_TEST_CYRUS"):
    targets.add(tgt)
  if targets.len == 0:
    return err(
      "no live targets configured — set JMAP_TEST_STALWART_*, JMAP_TEST_JAMES_*, " &
        "and/or JMAP_TEST_CYRUS_*"
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
