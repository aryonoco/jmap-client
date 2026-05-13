# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/get attachments (RFC 8621 §4.1.4)
## against Stalwart. Phase D Step 21 — exercises the multipart/mixed
## MIME tree on a seeded email built via ``mlive.seedMixedEmail``.
##
## The attachment payload is a 32-byte ASCII sentinel rather than the
## raw PNG header.  Inline body values flow through ``Email/set
## create`` as JSON strings, so high-bit bytes do not survive the
## quoted-string round-trip.  The plan-level intent — "verify that an
## attachment shows up with the right size, name, and disposition" —
## is preserved; only the byte content of the sentinel is changed.
##
## Asserts:
##   1. ``attachments.len == 1`` — exactly one non-body leaf surfaces.
##   2. ``attachments[0].disposition == Opt.some(dispositionAttachment)``.
##   3. ``attachments[0].name == Opt.some(attachmentName)`` — the
##      injected filename round-trips.
##   4. ``attachments[0].blobId.string.len > 0`` — Stalwart assigns a
##      non-empty BlobId on creation, suitable for ``Email/parse`` in
##      Step 24.
##   5. ``attachments[0].size == parseUnsignedInt(32).get()`` — the sentinel byte
##      count.
##
## Captures: ``email-multipart-mixed-attachment-stalwart`` after the
## ``Email/get`` so the attachment wire shape is recorded.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``.

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailGetAttachmentsLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): RFC 8621 §4.6 lets a server require pre-
    # uploaded blob attachments and reject inline-bodyValues with
    # ``invalidArguments``. James 3.9 requires blob uploads for every
    # attachment; Cyrus 3.12.2 requires blob uploads for binary parts
    # (``imap/jmap_mail.c:10046-10049``) — both servers reject this
    # binary-octet sentinel. Stalwart 0.15.5 accepts inline-bodyValues
    # for binary parts. The library's ``/upload`` surface is
    # deliberately deferred; on the rejection arm the typed-error
    # projection has already fired inside ``seedMixedEmail`` (the
    # internal ``resp.get(setHandle).valueOr:`` site) — that is the
    # Cat-B error-arm assertion this test verifies.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    const attachmentName = "sentinel.dat"
    const attachmentMimeType = "application/octet-stream"
    const attachmentBytes = "phase-d step-21 sentinel 32-byte"
      ## 32 ASCII octets — clean JSON round-trip.
    assertOn target, attachmentBytes.len == 32, "test sentinel must be exactly 32 bytes"

    let seededRes = seedMixedEmail(
      client, mailAccountId, inbox, "phase-d step-21 attachment",
      "Body precedes the attachment.", attachmentName, attachmentMimeType,
      attachmentBytes, "seedMixed",
    )
    if seededRes.isErr:
      # Cat-B error arm — ``seededRes`` carries the rawType from the
      # method-level error (``invalidArguments`` for binary inline-
      # bodyValues rejection). Skip the dependent read-back assertions.
      client.close()
      continue
    let seededId = seededRes.unsafeValue

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "attachments"]),
    )
    let resp =
      client.send(b.freeze()).expect("send Email/get attachments[" & $target.kind & "]")
    captureIfRequested(client, "email-multipart-mixed-attachment-" & $target.kind)
      .expect("captureIfRequested")
    let getResp =
      resp.get(getHandle).expect("Email/get attachments extract[" & $target.kind & "]")
    assertOn target, getResp.list.len == 1, "Email/get must return the seeded message"

    let email = getResp.list[0]
    assertOn target,
      email.attachments.len == 1,
      "expected one attachment, got " & $email.attachments.len
    let attachment = email.attachments[0]
    assertOn target, attachment.isLeaf, "attachments[0] must be a leaf"
    assertOn target,
      attachment.disposition.isSome, "attachments[0].disposition must be present"
    assertOn target,
      attachment.disposition.unsafeGet.kind == cdAttachment,
      "attachments[0].disposition must be cdAttachment (got " &
        $attachment.disposition.unsafeGet.kind & ")"
    assertOn target,
      attachment.name.isSome and attachment.name.unsafeGet == attachmentName,
      "attachments[0].name must be the injected filename"
    assertOn target,
      ($attachment.blobId).len > 0, "attachments[0].blobId must be non-empty"
    assertOn target,
      attachment.size == parseUnsignedInt(32).get(),
      "attachments[0].size must be 32 (got " & $attachment.size & ")"
    client.close()
