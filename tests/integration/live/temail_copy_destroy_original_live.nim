# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for compound ``Email/copy`` with implicit
## ``Email/set`` destroy of the source (RFC 8620 §5.4 + RFC 8621 §4.7)
## against Stalwart. Phase E Step 26 — exercises ``addEmailCopyAndDestroy``
## and the ``getBoth(EmailCopyHandles)`` extractor.
##
## Sequence:
##  1. Resolve inbox + idempotently resolve / create the
##     ``"phase-e step-26 archive"`` mailbox.
##  2. Seed a single text/plain email into the inbox.
##  3. ``Email/copy`` with ``onSuccessDestroyOriginal: true`` and
##     creation id ``"copy26"``; extract both responses via ``getBoth``.
##     Assert the primary copy succeeded and the implicit destroy of
##     the source succeeded.
##  4. ``Email/get`` the source id; assert it is reported in
##     ``notFound`` (RFC 8620 §5.1: nonexistent ids surface there).
##
## Capture: ``email-copy-destroy-original-stalwart`` after the compound
## send. Listed in ``tests/testament_skip.txt`` so ``just test`` skips
## it; run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file joins
## testament's megatest cleanly under ``just test-full`` when env vars
## are absent.

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
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

    # --- 1-2. Resolve inbox / archive, seed source -------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let archiveId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-e step-26 archive"
      )
      .expect("resolveOrCreateMailbox archive")
    let sourceId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-e step-26 mover", "seed26"
      )
      .expect("seedSimpleEmail mover")

    # --- 3. Compound Email/copy + implicit destroy --------------------------
    let copyCid = parseCreationId("copy26").expect("parseCreationId copy26")
    let archiveSet = parseNonEmptyMailboxIdSet(@[archiveId]).expect(
        "parseNonEmptyMailboxIdSet archive"
      )
    var createTbl = initTable[CreationId, EmailCopyItem]()
    createTbl[copyCid] =
      initEmailCopyItem(id = sourceId, mailboxIds = Opt.some(archiveSet))
    let (bCopy, handles) = addEmailCopyAndDestroy(
      initRequestBuilder(),
      fromAccountId = mailAccountId,
      accountId = mailAccountId,
      create = createTbl,
    )
    let respCopy = client.send(bCopy).expect("send Email/copy + destroy")
    captureIfRequested(client, "email-copy-destroy-original-stalwart").expect(
      "captureIfRequested"
    )
    let results = respCopy.getBoth(handles).expect("getBoth(EmailCopyHandles)")

    var copyOk = false
    results.primary.createResults.withValue(copyCid, outcome):
      doAssert outcome.isOk, "primary Email/copy must succeed: " & outcome.error.rawType
      copyOk = true
    do:
      doAssert false, "primary Email/copy must report an outcome for copy26"
    doAssert copyOk

    var sourceDestroyed = false
    results.implicit.destroyResults.withValue(sourceId, outcome):
      doAssert outcome.isOk,
        "implicit Email/set destroy of source must succeed: " & outcome.error.rawType
      sourceDestroyed = true
    do:
      doAssert false, "implicit Email/set must report a destroy outcome for sourceId"
    doAssert sourceDestroyed

    # --- 4. Source must surface in notFound --------------------------------
    let (bGet, getHandle) =
      addEmailGet(initRequestBuilder(), mailAccountId, ids = directIds(@[sourceId]))
    let respGet = client.send(bGet).expect("send Email/get source post-destroy")
    let getResp = respGet.get(getHandle).expect("Email/get source post-destroy extract")
    doAssert getResp.list.len == 0, "source must be gone after compound copy+destroy"
    var sawNotFound = false
    for nfId in getResp.notFound:
      if nfId == sourceId:
        sawNotFound = true
    doAssert sawNotFound,
      "destroyed source id must surface in Email/get notFound (RFC 8620 §5.1)"
    client.close()
