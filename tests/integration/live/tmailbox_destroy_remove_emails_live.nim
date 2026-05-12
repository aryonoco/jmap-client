# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Mailbox/set destroy`` with
## ``onDestroyRemoveEmails: true`` (RFC 8621 §2.5) against Stalwart.
## Phase E Step 30 — capstone closing the last live-suite gap. Phase B
## Step 10 proved structural emission of the flag; this test proves the
## *semantic* effect of the cascade (mailbox + every email it contained
## are gone) and the contrapositive sad path (no flag → setMailboxHasEmail).
##
## Three legs:
##
## **Leg A — happy path with cascade.**
##  1. Resolve / create ``"phase-e step-30 child-a"`` under inbox.
##  2. Seed three emails into it.
##  3. ``Mailbox/set destroy = [child-a]`` with
##     ``onDestroyRemoveEmails = true``. Assert success.
##  4. ``Mailbox/get`` and assert child-a is absent.
##  5. ``Email/get`` the seeded ids and assert each surfaces in
##     ``notFound`` (RFC 8621 §2.5: cascade removes the contained emails).
##
## **Leg B — sad path (no cascade flag).**
##  1. Resolve / create ``"phase-e step-30 child-b"`` under inbox.
##  2. Seed two emails into it.
##  3. ``Mailbox/set destroy = [child-b]`` (default
##     ``onDestroyRemoveEmails = false``). Assert error
##     ``setMailboxHasEmail`` (RFC 8621 §2.5).
##
## **Leg C — cleanup.**
##  Repeat leg A's destroy on child-b with
##  ``onDestroyRemoveEmails = true`` so subsequent runs see a clean
##  baseline.
##
## Capture: ``mailbox-set-destroy-with-emails-stalwart`` after leg A's
## Mailbox/set send. Listed in ``tests/testament_skip.txt`` so
## ``just test`` skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on ``loadLiveTestTargets().isOk``
## so the file joins testament's megatest cleanly under
## ``just test-full`` when env vars are absent.

import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tmailboxDestroyRemoveEmailsLive:
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

    # =====================================================================
    # Leg A — happy path with onDestroyRemoveEmails = true
    # =====================================================================
    let childAId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-e step-30 child-a"
      )
      .expect("resolveOrCreateMailbox child-a[" & $target.kind & "]")
    let seedAIds = seedEmailsIntoMailbox(
        client,
        mailAccountId,
        childAId,
        @["phase-e step-30 a-1", "phase-e step-30 a-2", "phase-e step-30 a-3"],
      )
      .expect("seedEmailsIntoMailbox child-a[" & $target.kind & "]")
    assertOn target,
      seedAIds.len == 3, "leg A must seed three emails (got " & $seedAIds.len & ")"

    let (bDestroyA, destroyAHandle) = addMailboxSet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      destroy = directIds(@[childAId]),
      onDestroyRemoveEmails = true,
    )
    let respDestroyA = client.send(bDestroyA.freeze()).expect(
        "send Mailbox/set destroy A[" & $target.kind & "]"
      )
    captureIfRequested(client, "mailbox-set-destroy-with-emails-" & $target.kind).expect(
      "captureIfRequested"
    )
    let destroyAResp = respDestroyA.get(destroyAHandle).expect(
        "Mailbox/set destroy A[" & $target.kind & "]"
      )
    var childADestroyed = false
    destroyAResp.destroyResults.withValue(childAId, outcome):
      assertOn target,
        outcome.isOk,
        "Mailbox/set destroy with cascade must succeed: " & outcome.error.rawType
      childADestroyed = true
    do:
      assertOn target, false, "Mailbox/set must report a destroy outcome for childAId"
    assertOn target, childADestroyed

    # Mailbox absence: enumerate all and assert child-a is gone.
    let (bGetA, getAHandle) =
      addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
    let respGetA = client.send(bGetA.freeze()).expect(
        "send Mailbox/get post-A[" & $target.kind & "]"
      )
    let mbResp = respGetA.get(getAHandle).expect(
        "Mailbox/get post-A extract[" & $target.kind & "]"
      )
    var sawChildA = false
    for mb in mbResp.list:
      if mb.id == childAId:
        sawChildA = true
    assertOn target,
      not sawChildA,
      "child-a mailbox must be absent after destroy with onDestroyRemoveEmails"

    # Email cascade: every seeded id must surface in notFound.
    let (bGetE, getEHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()), mailAccountId, ids = directIds(seedAIds)
    )
    let respGetE = client.send(bGetE.freeze()).expect(
        "send Email/get cascade-check[" & $target.kind & "]"
      )
    let getEResp = respGetE.get(getEHandle).expect(
        "Email/get cascade-check extract[" & $target.kind & "]"
      )
    assertOn target,
      getEResp.list.len == 0,
      "every seeded email under child-a must be cascaded; list must be empty"
    let notFoundSet = getEResp.notFound.toHashSet
    for sid in seedAIds:
      assertOn target,
        sid in notFoundSet,
        "seeded email " & string(sid) & " must surface in Email/get notFound"

    # =====================================================================
    # Leg B — sad path (no cascade flag → setMailboxHasEmail)
    # =====================================================================
    let childBId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-e step-30 child-b"
      )
      .expect("resolveOrCreateMailbox child-b[" & $target.kind & "]")
    let seedBIds = seedEmailsIntoMailbox(
        client, mailAccountId, childBId, @["phase-e step-30 b-1", "phase-e step-30 b-2"]
      )
      .expect("seedEmailsIntoMailbox child-b[" & $target.kind & "]")
    assertOn target,
      seedBIds.len == 2, "leg B must seed two emails (got " & $seedBIds.len & ")"

    let (bDestroyB, destroyBHandle) = addMailboxSet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      destroy = directIds(@[childBId]),
    )
    let respDestroyB = client.send(bDestroyB.freeze()).expect(
        "send Mailbox/set destroy B no-cascade[" & $target.kind & "]"
      )
    let destroyBResp = respDestroyB.get(destroyBHandle).expect(
        "Mailbox/set destroy B extract[" & $target.kind & "]"
      )
    var sawHasEmail = false
    destroyBResp.destroyResults.withValue(childBId, outcome):
      assertOn target,
        outcome.isErr,
        "destroying a non-empty mailbox without onDestroyRemoveEmails must fail"
      let setErr = outcome.error
      assertOn target,
        setErr.errorType == setMailboxHasEmail,
        "errorType must be setMailboxHasEmail per RFC 8621 §2.5; got rawType=" &
          setErr.rawType
      assertOn target,
        setErr.rawType == "mailboxHasEmail", "rawType must round-trip the wire literal"
      sawHasEmail = true
    do:
      assertOn target, false, "Mailbox/set destroy must report an outcome for childBId"
    assertOn target, sawHasEmail

    # =====================================================================
    # Leg C — cleanup of leg B's child
    # =====================================================================
    let (bCleanup, cleanupHandle) = addMailboxSet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      destroy = directIds(@[childBId]),
      onDestroyRemoveEmails = true,
    )
    let respCleanup = client.send(bCleanup.freeze()).expect(
        "send Mailbox/set cleanup B[" & $target.kind & "]"
      )
    let cleanupResp = respCleanup.get(cleanupHandle).expect(
        "Mailbox/set cleanup B extract[" & $target.kind & "]"
      )
    var childBCleaned = false
    cleanupResp.destroyResults.withValue(childBId, outcome):
      assertOn target,
        outcome.isOk,
        "cleanup destroy of child-b with cascade must succeed: " & outcome.error.rawType
      childBCleaned = true
    do:
      assertOn target, false, "cleanup must report a destroy outcome for childBId"
    assertOn target, childBCleaned
    client.close()
