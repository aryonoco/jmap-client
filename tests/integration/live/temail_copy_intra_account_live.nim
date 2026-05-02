# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Email/copy`` rejection when
## ``fromAccountId == accountId`` (RFC 8620 §5.4) against Stalwart.
## Phase E Step 25 — pins the wire contract for an RFC-mandated
## rejection.
##
## RFC 8620 §5.4 mandates that the destination ``accountId`` MUST
## differ from ``fromAccountId``: "The id of the account to copy
## records to. This MUST be different to the 'fromAccountId'."
## Stalwart 0.15.5 enforces this with a method-level
## ``metInvalidArguments`` error carrying the description "From
## accountId is equal to fromAccountId". The RFC does not enumerate
## a specific error variant for the constraint violation, so
## Stalwart's ``invalidArguments`` choice is pragmatic and
## RFC-aligned.
##
## This test pins the rejection wire shape so the client correctly
## handles an Email/copy issued against the same account on both
## sides — a common naive-caller mistake. The captured fixture feeds
## the always-on parser-only replay test that validates
## ``MethodError.fromJson`` against the rejection wire.
##
## Sequence:
##  1. Resolve inbox.
##  2. Seed a single text/plain email (the source-id need only be
##     real; the request will be rejected before any state change).
##  3. ``addEmailCopy`` with ``fromAccountId == accountId ==
##     mailAccountId``. Send. Capture
##     ``email-copy-intra-rejected-stalwart``.
##  4. Assert the response is a method-level error with
##     ``errorType == metInvalidArguments`` and ``rawType ==
##     "invalidArguments"``.
##  5. Cleanup: destroy the seed; assert success (the seed was
##     intact since the copy never reached storage).
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``. Body
## is guarded on ``loadLiveTestConfig().isOk`` so the file joins
## testament's megatest cleanly under ``just test-full`` when env
## vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailCopyIntraAccountLive:
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

    # --- 1-2. Resolve inbox + seed source ---------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let sourceId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-e step-25 source", "seed25"
      )
      .expect("seedSimpleEmail source")

    # --- 3. Issue the rejection-bound Email/copy --------------------------
    let copyCid = parseCreationId("copy25").expect("parseCreationId copy25")
    let inboxSet =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet inbox")
    var createTbl = initTable[CreationId, EmailCopyItem]()
    createTbl[copyCid] =
      initEmailCopyItem(id = sourceId, mailboxIds = Opt.some(inboxSet))
    let (bCopy, copyHandle) = addEmailCopy(
      initRequestBuilder(),
      fromAccountId = mailAccountId,
      accountId = mailAccountId,
      create = createTbl,
    )
    let respCopy = client.send(bCopy).expect("send Email/copy (rejection-bound)")
    captureIfRequested(client, "email-copy-intra-rejected-stalwart").expect(
      "captureIfRequested"
    )

    # --- 4. Assert rejection at method level ------------------------------
    let copyResult = respCopy.get(copyHandle)
    doAssert copyResult.isErr,
      "RFC 8620 §5.4 mandates accountId != fromAccountId; same-account Email/copy " &
        "must surface a method-level error"
    let methodErr = copyResult.error
    doAssert methodErr.errorType == metInvalidArguments,
      "Stalwart rejects same-account Email/copy with metInvalidArguments (got rawType=" &
        methodErr.rawType & ")"
    doAssert methodErr.rawType == "invalidArguments",
      "rawType must round-trip the wire literal"

    # --- 5. Cleanup: source must still exist -----------------------------
    let (bClean, cleanHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, destroy = directIds(@[sourceId]))
    let respClean = client.send(bClean).expect("send Email/set cleanup")
    let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
    var sourceDestroyed = false
    cleanResp.destroyResults.withValue(sourceId, outcome):
      doAssert outcome.isOk,
        "cleanup destroy of seed must succeed (the rejected copy did not destroy it)"
      sourceDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for sourceId"
    doAssert sourceDestroyed
    client.close()
