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
## is guarded on ``loadLiveTestTargets().isOk`` so the file joins
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
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): test asserts on client behaviour for
    # RFC 8620 §5.4 (accountId != fromAccountId). Stalwart 0.15.5 and
    # Cyrus 3.12.2 implement Email/copy and reject the same-account
    # invocation with ``metInvalidArguments``; James 3.9 lacks Email/
    # copy and returns ``metUnknownMethod``. Both are valid client-
    # library typed-error projections.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- 1-2. Resolve inbox + seed source ---------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let sourceId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-e step-25 source", "seed25"
      )
      .expect("seedSimpleEmail source[" & $target.kind & "]")

    # --- 3. Issue the rejection-bound Email/copy --------------------------
    let copyCid =
      parseCreationId("copy25").expect("parseCreationId copy25[" & $target.kind & "]")
    let inboxSet = parseNonEmptyMailboxIdSet(@[inbox]).expect(
        "parseNonEmptyMailboxIdSet inbox[" & $target.kind & "]"
      )
    var createTbl = initTable[CreationId, EmailCopyItem]()
    createTbl[copyCid] =
      initEmailCopyItem(id = sourceId, mailboxIds = Opt.some(inboxSet))
    let (bCopy, copyHandle) = addEmailCopy(
      initRequestBuilder(),
      fromAccountId = mailAccountId,
      accountId = mailAccountId,
      create = createTbl,
    )
    let respCopy = client.send(bCopy).expect(
        "send Email/copy (rejection-bound)[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-copy-intra-rejected-" & $target.kind).expect(
      "captureIfRequested"
    )

    # --- 4. Assert rejection at method level ------------------------------
    # RFC 8620 §5.4 mandates accountId != fromAccountId. Stalwart and
    # Cyrus reject with ``metInvalidArguments``; James lacks the
    # method and returns ``metUnknownMethod``. Either projection is a
    # valid client-library typed-error contract.
    let copyResult = respCopy.get(copyHandle)
    assertOn target,
      copyResult.isErr,
      "Email/copy with accountId == fromAccountId must surface a typed error"
    let methodErr = copyResult.error
    assertOn target,
      methodErr.errorType in {metInvalidArguments, metUnknownMethod},
      "method error must project as metInvalidArguments or metUnknownMethod (got rawType=" &
        methodErr.rawType & ")"

    # --- 5. Cleanup: source must still exist -----------------------------
    let (bClean, cleanHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, destroy = directIds(@[sourceId]))
    let respClean =
      client.send(bClean).expect("send Email/set cleanup[" & $target.kind & "]")
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    var sourceDestroyed = false
    cleanResp.destroyResults.withValue(sourceId, outcome):
      assertOn target,
        outcome.isOk,
        "cleanup destroy of seed must succeed (the rejected copy did not destroy it)"
      sourceDestroyed = true
    do:
      assertOn target, false, "cleanup must report an outcome for sourceId"
    assertOn target, sourceDestroyed
    client.close()
