# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 50 — first wire test of ``Email/changes`` with the
## ``maxChanges`` cap forcing ``hasMoreChanges == true``, plus the
## RFC 8620 §5.2 window-roll loop using the returned ``newState``
## until the client is fully up to date.  Phase B11 / H48 asserted
## ``hasMoreChanges == false`` at low cardinality; this closes the
## "promote to a future regression if Stalwart ever changes its
## default" deferral language.
##
## Workflow:
##
##  1. Capture baseline state via ``captureBaselineState[Email]``.
##  2. Seed N=10 emails to force at least one paginate at
##     ``maxChanges = 2`` — the floor the plan-doc anticipated for
##     Stalwart's collapse behaviour at low cardinality.
##  3. First page: ``addChanges[Email]`` with
##     ``maxChanges = Opt.some(MaxChanges(2))``.  Assert
##     ``hasMoreChanges == true`` and ``created.len + updated.len +
##     destroyed.len <= 2``.  Capture
##     ``email-changes-max-changes-stalwart``.
##  4. Window-roll: repeated ``Email/changes`` from each returned
##     ``newState`` until ``hasMoreChanges == false``.  Accumulate
##     created ids across all pages; assert all 10 seeded ids
##     surface in the union; final ``newState != baselineState``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestTargets().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/sets

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

const SeedCount = 10
const MaxChangesCap = 2
const MaxIters = 20

block temailChangesMaxChangesLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let baselineState = captureBaselineState[Email](client, mailAccountId).expect(
        "captureBaselineState[Email]"
      )

    var subjects: seq[string] = @[]
    for i in 0 ..< SeedCount:
      subjects.add("phase-i 50 m" & $i)
    let seededIds = seedEmailsWithSubjects(client, mailAccountId, inbox, subjects)
      .expect("seedEmailsWithSubjects[" & $target.kind & "]")
    assertOn target,
      seededIds.len == SeedCount, "ten seeded ids expected (got " & $seededIds.len & ")"

    let maxChangesCap = Opt.some(
      parseMaxChanges(UnsignedInt(MaxChangesCap)).expect(
        "parseMaxChanges[" & $target.kind & "]"
      )
    )

    # First page — capture against a fresh seed surface so
    # hasMoreChanges is forced true.
    let (b1, h1) = addEmailChanges(
      initRequestBuilder(),
      mailAccountId,
      sinceState = baselineState,
      maxChanges = maxChangesCap,
    )
    let resp1 =
      client.send(b1).expect("send Email/changes first page[" & $target.kind & "]")
    captureIfRequested(client, "email-changes-max-changes-" & $target.kind).expect(
      "captureIfRequested"
    )
    let cr1 =
      resp1.get(h1).expect("Email/changes first page extract[" & $target.kind & "]")
    assertOn target,
      cr1.hasMoreChanges,
      "maxChanges=2 against ten seeded emails must force hasMoreChanges=true"
    assertOn target,
      cr1.created.len + cr1.updated.len + cr1.destroyed.len <= MaxChangesCap,
      "first page total <= maxChanges (got created=" & $cr1.created.len & " updated=" &
        $cr1.updated.len & " destroyed=" & $cr1.destroyed.len & ")"

    # Window-roll loop until hasMoreChanges == false.
    var seenIds = initHashSet[Id]()
    for id in cr1.created:
      seenIds.incl(id)
    for id in cr1.updated:
      seenIds.incl(id)
    var nextState = cr1.newState
    var hasMore = cr1.hasMoreChanges
    var iter = 0
    while hasMore and iter < MaxIters:
      let (bN, hN) = addEmailChanges(
        initRequestBuilder(),
        mailAccountId,
        sinceState = nextState,
        maxChanges = maxChangesCap,
      )
      let respN =
        client.send(bN).expect("send Email/changes window-roll[" & $target.kind & "]")
      let crN =
        respN.get(hN).expect("Email/changes window-roll extract[" & $target.kind & "]")
      for id in crN.created:
        seenIds.incl(id)
      for id in crN.updated:
        seenIds.incl(id)
      nextState = crN.newState
      hasMore = crN.hasMoreChanges
      iter.inc
    assertOn target,
      not hasMore, "window-roll loop must converge within " & $MaxIters & " iterations"
    for sid in seededIds:
      assertOn target,
        sid in seenIds,
        "seeded id " & string(sid) & " must appear across paginated changes"
    assertOn target,
      string(nextState) != string(baselineState),
      "final newState must differ from the original baseline"

    client.close()
