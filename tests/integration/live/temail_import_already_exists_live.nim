# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for ``Email/import`` with duplicate dedup
## tuple against Stalwart (RFC 8621 §4.8). Phase E Step 28 — pins
## Stalwart's no-dedup behaviour and validates the RFC's
## "separate-id" mandate.
##
## RFC 8621 §4.8 makes dedup permissive (lines 3031-3038):
##
##   "The server MAY forbid two Email objects with the same exact
##   content [RFC5322], or even just with the same Message-ID
##   [RFC5322], to coexist within an account. … If duplicates are
##   allowed, the newly created Email object MUST have a separate
##   id and independent mutable properties to the existing object."
##
## Stalwart 0.15.5 takes the MAY-permits path: a second import with
## an identical ``(blobId, mailboxIds, keywords, receivedAt)`` tuple
## succeeds with a fresh server-assigned ``Id``. Both imports are
## valid; neither errors. The test pins this wire shape and asserts
## the RFC's "separate-id" mandate.
##
## The dedup-rejection branch (the err path with ``setAlreadyExists``
## and ``existingId``) is covered at the parser layer by the
## smart-constructor and round-trip tests in
## ``tests/serde/mail/tserde_email_import.nim``. The codebase is
## dedup-ready; this live test pins Stalwart's actual behaviour.
##
## Sequence:
##  1. Resolve inbox; seed mixed email; acquire ``attachmentBlobId``
##     via ``mlive.getFirstAttachmentBlobId``.
##  2. **First Email/import** with
##     ``receivedAt = parseUtcDate("2026-05-01T00:00:00Z")`` and
##     creation id ``"import28a"``. Assert ``isOk``.
##  3. **Second Email/import** with identical ``receivedAt`` and
##     creation id ``"import28b"``. Capture
##     ``email-import-no-dedup-stalwart`` after the send. Assert
##     ``isOk`` AND ``firstImportedId != secondImportedId`` (RFC 8621
##     §4.8 separate-id mandate).
##  4. Cleanup: destroy ``[seed, firstImportedId, secondImportedId]``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``. Body
## is guarded on ``loadLiveTestTargets().isOk`` so the file joins
## testament's megatest cleanly under ``just test-full`` when env
## vars are absent.

import std/tables

import results
import jmap_client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailImportAlreadyExistsLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): the seed step uses inline-bodyValues that
    # James 3.9 rejects with ``invalidArguments``; Stalwart 0.15.5 and
    # Cyrus 3.12.2 (text/* parts) accept them. RFC 8621 §4.8 makes
    # dedup permissive — Stalwart and Cyrus take the MAY-permits path.
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- 1. Seed mixed email + capture attachment blobId -------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    const attachmentBytes = "phase-e step-28 attachment 32-b!"
      ## 32 ASCII octets — clean JSON round-trip (Phase D Step 21 precedent).
    assertOn target,
      attachmentBytes.len == 32, "attachment sentinel must be exactly 32 bytes"
    let sourceRes = seedMixedEmail(
      client, mailAccountId, inbox, "phase-e step-28 source",
      "Body precedes the attachment.", "phase-e-source.txt", "text/plain",
      attachmentBytes, "seed28src",
    )
    if sourceRes.isErr:
      continue
    let sourceId = sourceRes.unsafeValue
    let attachmentBlobId = getFirstAttachmentBlobId(client, mailAccountId, sourceId)
      .expect("getFirstAttachmentBlobId[" & $target.kind & "]")
    let inboxSet = parseNonEmptyMailboxIdSet(@[inbox]).expect(
        "parseNonEmptyMailboxIdSet inbox[" & $target.kind & "]"
      )
    let receivedAt =
      parseUtcDate("2026-05-01T00:00:00Z").expect("parseUtcDate[" & $target.kind & "]")

    # --- 2. First Email/import ---------------------------------------------
    let firstCid = parseCreationId("import28a").expect(
        "parseCreationId import28a[" & $target.kind & "]"
      )
    let firstItem = initEmailImportItem(
      blobId = attachmentBlobId,
      mailboxIds = inboxSet,
      receivedAt = Opt.some(receivedAt),
    )
    let firstMap = initNonEmptyEmailImportMap(@[(firstCid, firstItem)]).expect(
        "initNonEmptyEmailImportMap first"
      )
    let (bFirst, firstHandle) = addEmailImport(
      initRequestBuilder(makeBuilderId()), mailAccountId, emails = firstMap
    )
    let respFirst = client.send(bFirst.freeze()).expect(
        "send Email/import first[" & $target.kind & "]"
      )
    let firstResp = respFirst.get(firstHandle).expect(
        "Email/import first extract[" & $target.kind & "]"
      )
    var firstImportedId: Id
    var firstOk = false
    firstResp.createResults.withValue(firstCid, outcome):
      if outcome.isOk:
        firstImportedId = outcome.unsafeValue.id
        firstOk = true
      else:
        # Cat-B Cell-error arm: server rejected Email/import for the
        # seeded blob (Cyrus 3.12.2 may reject blobs not produced by
        # an explicit ``/upload`` path with ``invalidEmail``). The
        # client correctly projected the typed SetError; skip the
        # second-import / dedup assertions.
        discard outcome.unsafeError
    do:
      assertOn target, false, "first Email/import must report an outcome for import28a"
    if not firstOk:
      continue

    # --- 3. Second Email/import with identical dedup tuple ----------------
    let secondCid = parseCreationId("import28b").expect(
        "parseCreationId import28b[" & $target.kind & "]"
      )
    let secondItem = initEmailImportItem(
      blobId = attachmentBlobId,
      mailboxIds = inboxSet,
      receivedAt = Opt.some(receivedAt),
    )
    let secondMap = initNonEmptyEmailImportMap(@[(secondCid, secondItem)]).expect(
        "initNonEmptyEmailImportMap second"
      )
    let (bSecond, secondHandle) = addEmailImport(
      initRequestBuilder(makeBuilderId()), mailAccountId, emails = secondMap
    )
    let respSecond = client.send(bSecond.freeze()).expect(
        "send Email/import second[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "email-import-no-dedup-" & $target.kind
    )
      .expect("captureIfRequested")
    let secondResp = respSecond.get(secondHandle).expect(
        "Email/import second extract[" & $target.kind & "]"
      )
    var secondImportedId: Id
    var secondOk = false
    secondResp.createResults.withValue(secondCid, outcome):
      if outcome.isOk:
        secondImportedId = outcome.unsafeValue.id
        secondOk = true
      else:
        # Cat-B SetError arm — server forbids dedup-tuple duplicates
        # (the alternative RFC 8621 §4.8 branch). The client correctly
        # projected the typed SetError; skip the separate-id assertion.
        discard outcome.unsafeError
    do:
      assertOn target, false, "second Email/import must report an outcome for import28b"
    if secondOk:
      assertOn target,
        $firstImportedId != $secondImportedId,
        "RFC 8621 §4.8 mandates separate ids for permitted duplicates: " &
          "firstImportedId=" & $firstImportedId & " == secondImportedId=" &
          $secondImportedId

    # --- 4. Cleanup: destroy [seed, first, second] ------------------------
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      destroy = directIds(@[sourceId, firstImportedId, secondImportedId]),
    )
    let respClean = client.send(bClean.freeze()).expect(
        "send Email/set cleanup[" & $target.kind & "]"
      )
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    for cleanupId in [sourceId, firstImportedId, secondImportedId]:
      var destroyed = false
      cleanResp.destroyResults.withValue(cleanupId, outcome):
        assertOn target,
          outcome.isOk,
          "cleanup destroy of " & $cleanupId & " must succeed: " & outcome.error.rawType
        destroyed = true
      do:
        assertOn target, false, "cleanup must report an outcome for " & $cleanupId
      assertOn target, destroyed
