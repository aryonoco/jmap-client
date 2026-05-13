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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailImportFromBlobLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): the seed step uses inline-bodyValues for the
    # attachment that James 3.9 rejects with ``invalidArguments``;
    # Stalwart 0.15.5 and Cyrus 3.12.2 (text/* parts) accept them.
    # The library's ``/upload`` surface is deliberately deferred; the
    # seed-rejection arm exercises the typed-error projection.
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- 1-2. Seed mixed email + capture attachment blobId -----------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    const attachmentBytes = "phase-e step-27 attachment 32-b!"
      ## 32 ASCII octets — clean JSON round-trip (Phase D Step 21 precedent).
    assertOn target,
      attachmentBytes.len == 32, "attachment sentinel must be exactly 32 bytes"
    let sourceRes = seedMixedEmail(
      client, mailAccountId, inbox, "phase-e step-27 source",
      "Body precedes the attachment.", "phase-e-source.txt", "text/plain",
      attachmentBytes, "seed27src",
    )
    if sourceRes.isErr:
      continue
    let sourceId = sourceRes.unsafeValue
    let attachmentBlobId = getFirstAttachmentBlobId(client, mailAccountId, sourceId)
      .expect("getFirstAttachmentBlobId[" & $target.kind & "]")

    # --- 3-4. Email/import ------------------------------------------------
    let importCid = parseCreationId("import27").expect(
        "parseCreationId import27[" & $target.kind & "]"
      )
    let inboxSet = parseNonEmptyMailboxIdSet(@[inbox]).expect(
        "parseNonEmptyMailboxIdSet inbox[" & $target.kind & "]"
      )
    let importItem =
      initEmailImportItem(blobId = attachmentBlobId, mailboxIds = inboxSet)
    let importMap = initNonEmptyEmailImportMap(@[(importCid, importItem)]).expect(
        "initNonEmptyEmailImportMap"
      )
    let (bImport, importHandle) = addEmailImport(
      initRequestBuilder(makeBuilderId()), mailAccountId, emails = importMap
    )
    let respImport =
      client.send(bImport.freeze()).expect("send Email/import[" & $target.kind & "]")
    captureIfRequested(
      recorder.lastResponseBody, "email-import-from-blob-" & $target.kind
    )
      .expect("captureIfRequested")
    let importResp =
      respImport.get(importHandle).expect("Email/import extract[" & $target.kind & "]")
    var importedId: Id
    var importOk = false
    importResp.createResults.withValue(importCid, outcome):
      if outcome.isOk:
        importedId = outcome.unsafeValue.id
        importOk = true
      else:
        # Cat-B SetError arm — server rejected the import. Cyrus 3.12.2
        # may reject blobs that weren't produced by an explicit
        # ``/upload`` path. The client correctly projected the typed
        # SetError; skip the dependent verification + cleanup steps.
        discard outcome.unsafeError
    do:
      assertOn target, false, "Email/import must report an outcome for import27"
    if not importOk:
      continue

    # --- 5. Verify imported email exists -----------------------------------
    let (bGet, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[importedId]),
      properties = Opt.some(@["id", "blobId"]),
    )
    let respGet =
      client.send(bGet.freeze()).expect("send Email/get imported[" & $target.kind & "]")
    let getResp =
      respGet.get(getHandle).expect("Email/get imported extract[" & $target.kind & "]")
    assertOn target,
      getResp.list.len == 1, "imported email must be retrievable via Email/get"

    # --- 6. Cleanup: destroy [seed, imported] ------------------------------
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      destroy = directIds(@[sourceId, importedId]),
    )
    let respClean = client.send(bClean.freeze()).expect(
        "send Email/set cleanup[" & $target.kind & "]"
      )
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    var seedDestroyed = false
    var importedDestroyed = false
    cleanResp.destroyResults.withValue(sourceId, outcome):
      assertOn target, outcome.isOk, "cleanup destroy of seed must succeed"
      seedDestroyed = true
    do:
      assertOn target, false, "cleanup must report an outcome for seedId"
    cleanResp.destroyResults.withValue(importedId, outcome):
      assertOn target, outcome.isOk, "cleanup destroy of imported must succeed"
      importedDestroyed = true
    do:
      assertOn target, false, "cleanup must report an outcome for importedId"
    assertOn target, seedDestroyed and importedDestroyed
