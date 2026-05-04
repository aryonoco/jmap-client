# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for compound ``Email/copy`` with implicit
## ``Email/set`` destroy when ``fromAccountId == accountId`` (RFC 8620
## §5.4) against Stalwart. Phase E Step 26 — pins the compound
## rejection wire shape.
##
## Same RFC mandate as Step 25: RFC 8620 §5.4 forbids same-account
## copy. The compound ``addEmailCopyAndDestroy`` builder issues
## Email/copy with ``onSuccessDestroyOriginal: true``; Stalwart 0.15.5
## rejects the request at the method level (before any implicit
## destroy can fire), surfacing ``metInvalidArguments``.
##
## This test pins the compound rejection wire shape so the client
## correctly handles a compound copy+destroy issued naively against
## the same account on both sides. The captured fixture feeds the
## always-on parser-only replay test that validates
## ``MethodError.fromJson`` against the rejection wire.
##
## Sequence:
##  1. Resolve inbox.
##  2. Seed a single text/plain email.
##  3. ``addEmailCopyAndDestroy`` with ``fromAccountId == accountId
##     == mailAccountId``. Send. Capture
##     ``email-copy-destroy-original-rejected-stalwart``.
##  4. Assert ``resp.getBoth(handles).isErr`` AND
##     ``methodErr.errorType == metInvalidArguments``.
##  5. Cleanup: destroy the seed; assert success — the source
##     survived because the rejection occurred before any state
##     change.
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

block temailCopyDestroyOriginalLive:
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
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")

    # --- 1-2. Resolve inbox + seed source ---------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let sourceId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-e step-26 source", "seed26"
      )
      .expect("seedSimpleEmail source")

    # --- 3. Issue the rejection-bound compound copy+destroy ---------------
    let copyCid = parseCreationId("copy26").expect("parseCreationId copy26")
    let inboxSet =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet inbox")
    var createTbl = initTable[CreationId, EmailCopyItem]()
    createTbl[copyCid] =
      initEmailCopyItem(id = sourceId, mailboxIds = Opt.some(inboxSet))
    let (bCopy, handles) = addEmailCopyAndDestroy(
      initRequestBuilder(),
      fromAccountId = mailAccountId,
      accountId = mailAccountId,
      create = createTbl,
    )
    let respCopy =
      client.send(bCopy).expect("send Email/copy + destroy (rejection-bound)")
    captureIfRequested(client, "email-copy-destroy-original-rejected-stalwart").expect(
      "captureIfRequested"
    )

    # --- 4. Assert compound rejection at method level --------------------
    let bothResult = respCopy.getBoth(handles)
    doAssert bothResult.isErr,
      "RFC 8620 §5.4 mandates accountId != fromAccountId; compound same-account " &
        "copy+destroy must surface a method-level error"
    let methodErr = bothResult.error
    doAssert methodErr.errorType == metInvalidArguments,
      "Stalwart rejects compound same-account copy with metInvalidArguments (got rawType=" &
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
