# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for intra-account ``Email/copy`` (RFC 8621 §4.7,
## RFC 8620 §5.4) against Stalwart. Phase E Step 25 — first read-side
## proof that ``addEmailCopy``'s simple overload survives the wire round
## trip with ``destroyMode = keepOriginals()``: the source email remains,
## the copy lands in the archive mailbox under a new ``Id`` but with the
## same ``blobId`` (RFC 8621 §5.4 immutable-octets invariant).
##
## Sequence:
##  1. Resolve inbox + idempotently resolve / create the
##     ``"phase-e step-25 archive"`` mailbox.
##  2. Seed a single text/plain email into the inbox.
##  3. Capture its ``blobId`` via ``Email/get``.
##  4. ``Email/copy`` (simple overload — no implicit destroy) into the
##     archive mailbox with creation id ``"copy25"``.
##  5. ``Email/get`` the copied id; assert the ``blobId`` matches the
##     source (immutable-octets) and ``mailboxIds`` contains the archive.
##  6. ``Email/get`` the source id; assert it survived (single result,
##     ``destroyMode = keepOriginals()`` semantics).
##  7. Cleanup: destroy both copied and source ids; assert success on
##     each so re-runs see a clean baseline.
##
## Capture: ``email-copy-intra-stalwart`` after the copy send.
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/json
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

    # --- 1-2. Resolve inbox / archive, seed source -------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let archiveId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-e step-25 archive"
      )
      .expect("resolveOrCreateMailbox archive")
    let sourceId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-e step-25 source", "seed25"
      )
      .expect("seedSimpleEmail source")

    # --- 3. Capture source blobId ------------------------------------------
    let (bGetSrc, getSrcHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[sourceId]),
      properties = Opt.some(@["id", "blobId"]),
    )
    let respGetSrc = client.send(bGetSrc).expect("send Email/get source blobId")
    let getSrcResp = respGetSrc.get(getSrcHandle).expect("Email/get source extract")
    doAssert getSrcResp.list.len == 1, "Email/get must return the seeded source"
    let sourceBlobIdRaw = getSrcResp.list[0]{"blobId"}.getStr("")
    doAssert sourceBlobIdRaw.len > 0, "source blobId must be non-empty"

    # --- 4. Email/copy into the archive ------------------------------------
    let copyCid = parseCreationId("copy25").expect("parseCreationId copy25")
    let archiveSet = parseNonEmptyMailboxIdSet(@[archiveId]).expect(
        "parseNonEmptyMailboxIdSet archive"
      )
    var createTbl = initTable[CreationId, EmailCopyItem]()
    createTbl[copyCid] =
      initEmailCopyItem(id = sourceId, mailboxIds = Opt.some(archiveSet))
    let (bCopy, copyHandle) = addEmailCopy(
      initRequestBuilder(),
      fromAccountId = mailAccountId,
      accountId = mailAccountId,
      create = createTbl,
    )
    let respCopy = client.send(bCopy).expect("send Email/copy")
    captureIfRequested(client, "email-copy-intra-stalwart").expect("captureIfRequested")
    let copyResp = respCopy.get(copyHandle).expect("Email/copy extract")
    var copiedId: Id
    var copiedOk = false
    copyResp.createResults.withValue(copyCid, outcome):
      doAssert outcome.isOk, "Email/copy must succeed: " & outcome.error.rawType
      copiedId = outcome.unsafeValue.id
      copiedOk = true
    do:
      doAssert false, "Email/copy must report an outcome for copy25"
    doAssert copiedOk

    # --- 5. Verify copy carries the same blobId + archive membership -------
    let (bGetCopy, getCopyHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[copiedId]),
      properties = Opt.some(@["id", "blobId", "mailboxIds"]),
    )
    let respGetCopy = client.send(bGetCopy).expect("send Email/get copy")
    let getCopyResp = respGetCopy.get(getCopyHandle).expect("Email/get copy extract")
    doAssert getCopyResp.list.len == 1, "Email/get must return the copied email"
    let copiedNode = getCopyResp.list[0]
    doAssert copiedNode{"blobId"}.getStr("") == sourceBlobIdRaw,
      "copied blobId must match source (RFC 8621 §5.4 immutable octets)"
    let mailboxesNode = copiedNode{"mailboxIds"}
    doAssert not mailboxesNode.isNil and mailboxesNode.kind == JObject,
      "mailboxIds must be a JObject"
    var sawArchive = false
    for k, _ in mailboxesNode.pairs:
      if k == string(archiveId):
        sawArchive = true
    doAssert sawArchive, "copied email must be filed in the archive mailbox"

    # --- 6. Source must still exist ----------------------------------------
    let (bGetSrc2, getSrc2Handle) =
      addEmailGet(initRequestBuilder(), mailAccountId, ids = directIds(@[sourceId]))
    let respGetSrc2 = client.send(bGetSrc2).expect("send Email/get source survive")
    let getSrc2Resp = respGetSrc2.get(getSrc2Handle).expect("Email/get source survive")
    doAssert getSrc2Resp.list.len == 1,
      "source must survive Email/copy with destroyMode=keepOriginals()"

    # --- 7. Cleanup: destroy [copy, source] --------------------------------
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[copiedId, sourceId])
    )
    let respClean = client.send(bClean).expect("send Email/set cleanup")
    let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
    var copiedDestroyed = false
    var sourceDestroyed = false
    cleanResp.destroyResults.withValue(copiedId, outcome):
      doAssert outcome.isOk, "cleanup destroy of copy must succeed"
      copiedDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for copiedId"
    cleanResp.destroyResults.withValue(sourceId, outcome):
      doAssert outcome.isOk, "cleanup destroy of source must succeed"
      sourceDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for sourceId"
    doAssert copiedDestroyed and sourceDestroyed
    client.close()
