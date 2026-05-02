# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Email/import`` ``alreadyExists`` (RFC 8621
## §4.8 / RFC 8620 §5.4) against Stalwart. Phase E Step 28 — exercises
## the dedup constraint: importing the same ``(blobId, mailboxIds,
## keywords, receivedAt)`` tuple twice surfaces ``setAlreadyExists`` on
## the second call, with ``existingId`` pointing at the first imported
## email.
##
## Re-runnability handling: on a fresh Stalwart the first import
## succeeds and the second errors ``alreadyExists``. On a re-run against
## a Stalwart instance that already saw a Step 28 run, both imports
## error ``alreadyExists`` because the dedup tuple already matches a
## prior run's surviving email. The test ``case``-dispatches on the
## first import's outcome to bind ``originalImportedId``; the
## RFC-mandated assertion (second import is err with ``setAlreadyExists``
## and ``existingId == originalImportedId``) holds unconditionally.
##
## Sequence:
##  1. Resolve inbox; seed mixed email + acquire ``attachmentBlobId``
##     (mirrors Step 27 segments 1-3).
##  2. First Email/import with ``receivedAt = 2026-05-01T00:00:00Z`` and
##     creation id ``"import28a"``. ``case``-dispatch on the outcome:
##     - Ok: ``originalImportedId = outcome.unsafeValue.id``.
##     - Err setAlreadyExists: ``originalImportedId = setErr.existingId``.
##     - Err other: ``doAssert false``.
##  3. Second Email/import with the same ``receivedAt`` and creation id
##     ``"import28b"``. Assert (unconditional, RFC-mandated): the
##     outcome is err with errorType==setAlreadyExists, rawType==
##     "alreadyExists", and existingId==originalImportedId.
##  4. Cleanup: destroy [seed, originalImportedId].
##
## Capture: ``email-import-already-exists-stalwart`` after the second
## import send (the first import's response varies by re-run state; the
## second is identical regardless). Listed in ``tests/testament_skip.txt``
## so ``just test`` skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on ``loadLiveTestConfig().isOk``
## so the file joins testament's megatest cleanly under ``just test-full``
## when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailImportAlreadyExistsLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

    # --- 1. Seed mixed email + capture attachment blobId -------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    const attachmentBytes = "phase-e step-28 attachment 32-b!"
      ## 32 ASCII octets — clean JSON round-trip (Phase D Step 21 precedent).
    doAssert attachmentBytes.len == 32, "attachment sentinel must be exactly 32 bytes"
    let sourceId = seedMixedEmail(
        client, mailAccountId, inbox, "phase-e step-28 source",
        "Body precedes the attachment.", "phase-e-source.txt", "text/plain",
        attachmentBytes, "seed28src",
      )
      .expect("seedMixedEmail source")
    let attachmentBlobId = getFirstAttachmentBlobId(client, mailAccountId, sourceId)
      .expect("getFirstAttachmentBlobId")
    let inboxSet =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet inbox")
    let receivedAt = parseUtcDate("2026-05-01T00:00:00Z").expect("parseUtcDate")

    # --- 2. First Email/import (case-dispatch on outcome) ------------------
    let firstCid = parseCreationId("import28a").expect("parseCreationId import28a")
    let firstItem = initEmailImportItem(
      blobId = attachmentBlobId,
      mailboxIds = inboxSet,
      receivedAt = Opt.some(receivedAt),
    )
    let firstMap = initNonEmptyEmailImportMap(@[(firstCid, firstItem)]).expect(
        "initNonEmptyEmailImportMap first"
      )
    let (bFirst, firstHandle) =
      addEmailImport(initRequestBuilder(), mailAccountId, emails = firstMap)
    let respFirst = client.send(bFirst).expect("send Email/import first")
    let firstResp = respFirst.get(firstHandle).expect("Email/import first extract")
    var originalImportedId: Id
    var originalBound = false
    firstResp.createResults.withValue(firstCid, outcome):
      if outcome.isOk:
        originalImportedId = outcome.unsafeValue.id
        originalBound = true
      else:
        let setErr = outcome.error
        doAssert setErr.errorType == setAlreadyExists,
          "first-import error must be setAlreadyExists on re-run; got rawType=" &
            setErr.rawType
        originalImportedId = setErr.existingId
        originalBound = true
    do:
      doAssert false, "first Email/import must report an outcome for import28a"
    doAssert originalBound

    # --- 3. Second Email/import (RFC-mandated alreadyExists) ---------------
    let secondCid = parseCreationId("import28b").expect("parseCreationId import28b")
    let secondItem = initEmailImportItem(
      blobId = attachmentBlobId,
      mailboxIds = inboxSet,
      receivedAt = Opt.some(receivedAt),
    )
    let secondMap = initNonEmptyEmailImportMap(@[(secondCid, secondItem)]).expect(
        "initNonEmptyEmailImportMap second"
      )
    let (bSecond, secondHandle) =
      addEmailImport(initRequestBuilder(), mailAccountId, emails = secondMap)
    let respSecond = client.send(bSecond).expect("send Email/import second")
    captureIfRequested(client, "email-import-already-exists-stalwart").expect(
      "captureIfRequested"
    )
    let secondResp = respSecond.get(secondHandle).expect("Email/import second extract")
    var sawAlreadyExists = false
    secondResp.createResults.withValue(secondCid, outcome):
      doAssert outcome.isErr,
        "second Email/import must surface alreadyExists per RFC 8621 §4.8 dedup"
      let setErr = outcome.error
      doAssert setErr.errorType == setAlreadyExists,
        "second-import errorType must be setAlreadyExists; got rawType=" & setErr.rawType
      doAssert setErr.rawType == "alreadyExists",
        "rawType must round-trip the wire literal"
      doAssert setErr.existingId == originalImportedId,
        "existingId must point at the surviving original import"
      sawAlreadyExists = true
    do:
      doAssert false, "second Email/import must report an outcome for import28b"
    doAssert sawAlreadyExists

    # --- 4. Cleanup: destroy [seed, originalImported] ----------------------
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(),
      mailAccountId,
      destroy = directIds(@[sourceId, originalImportedId]),
    )
    let respClean = client.send(bClean).expect("send Email/set cleanup")
    let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
    var seedDestroyed = false
    var originalDestroyed = false
    cleanResp.destroyResults.withValue(sourceId, outcome):
      doAssert outcome.isOk, "cleanup destroy of seed must succeed"
      seedDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for seedId"
    cleanResp.destroyResults.withValue(originalImportedId, outcome):
      doAssert outcome.isOk, "cleanup destroy of original import must succeed"
      originalDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for originalImportedId"
    doAssert seedDestroyed and originalDestroyed
    client.close()
