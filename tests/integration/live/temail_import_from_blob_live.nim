# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Email/import`` (RFC 8621 §4.8) against
## Stalwart. Phase E Step 27 — exercises the happy-path Email/import
## flow without going through a separate blob upload endpoint: a seeded
## multipart/mixed email exposes its attachment as a fresh ``BlobId``,
## which then becomes the ``blobId`` of the imported email.
##
## Sequence:
##  1. Resolve inbox; seed a multipart/mixed email with a 32-byte ASCII
##     attachment via ``mlive.seedMixedEmail``.
##  2. Capture the attachment's ``BlobId`` via
##     ``mlive.getFirstAttachmentBlobId``.
##  3. Build a one-entry ``NonEmptyEmailImportMap`` with creation id
##     ``"import27"`` targeting the inbox and the attachment ``blobId``.
##  4. ``Email/import``; assert the create succeeded and bind the
##     ``importedId``.
##  5. ``Email/get`` the importedId; assert it surfaces (the imported
##     email exists).
##  6. Cleanup: destroy [seed, imported].
##
## Capture: ``email-import-from-blob-stalwart`` after the import send.
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailImportFromBlobLive:
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

    # --- 1-2. Seed mixed email + capture attachment blobId -----------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    const attachmentBytes = "phase-e step-27 attachment 32-b!"
      ## 32 ASCII octets — clean JSON round-trip (Phase D Step 21 precedent).
    doAssert attachmentBytes.len == 32, "attachment sentinel must be exactly 32 bytes"
    let sourceId = seedMixedEmail(
        client, mailAccountId, inbox, "phase-e step-27 source",
        "Body precedes the attachment.", "phase-e-source.txt", "text/plain",
        attachmentBytes, "seed27src",
      )
      .expect("seedMixedEmail source")
    let attachmentBlobId = getFirstAttachmentBlobId(client, mailAccountId, sourceId)
      .expect("getFirstAttachmentBlobId")

    # --- 3-4. Email/import ------------------------------------------------
    let importCid = parseCreationId("import27").expect("parseCreationId import27")
    let inboxSet =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet inbox")
    let importItem =
      initEmailImportItem(blobId = attachmentBlobId, mailboxIds = inboxSet)
    let importMap = initNonEmptyEmailImportMap(@[(importCid, importItem)]).expect(
        "initNonEmptyEmailImportMap"
      )
    let (bImport, importHandle) =
      addEmailImport(initRequestBuilder(), mailAccountId, emails = importMap)
    let respImport = client.send(bImport).expect("send Email/import")
    captureIfRequested(client, "email-import-from-blob-stalwart").expect(
      "captureIfRequested"
    )
    let importResp = respImport.get(importHandle).expect("Email/import extract")
    var importedId: Id
    var importOk = false
    importResp.createResults.withValue(importCid, outcome):
      doAssert outcome.isOk, "Email/import must succeed: " & outcome.error.rawType
      importedId = outcome.unsafeValue.id
      importOk = true
    do:
      doAssert false, "Email/import must report an outcome for import27"
    doAssert importOk

    # --- 5. Verify imported email exists -----------------------------------
    let (bGet, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[importedId]),
      properties = Opt.some(@["id", "blobId"]),
    )
    let respGet = client.send(bGet).expect("send Email/get imported")
    let getResp = respGet.get(getHandle).expect("Email/get imported extract")
    doAssert getResp.list.len == 1, "imported email must be retrievable via Email/get"

    # --- 6. Cleanup: destroy [seed, imported] ------------------------------
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[sourceId, importedId])
    )
    let respClean = client.send(bClean).expect("send Email/set cleanup")
    let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
    var seedDestroyed = false
    var importedDestroyed = false
    cleanResp.destroyResults.withValue(sourceId, outcome):
      doAssert outcome.isOk, "cleanup destroy of seed must succeed"
      seedDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for seedId"
    cleanResp.destroyResults.withValue(importedId, outcome):
      doAssert outcome.isOk, "cleanup destroy of imported must succeed"
      importedDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for importedId"
    doAssert seedDestroyed and importedDestroyed
    client.close()
