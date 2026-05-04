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
##   5. ``attachments[0].size == UnsignedInt(32)`` — the sentinel byte
##      count.
##
## Captures: ``email-multipart-mixed-attachment-stalwart`` after the
## ``Email/get`` so the attachment wire shape is recorded.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailGetAttachmentsLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    const attachmentName = "sentinel.dat"
    const attachmentMimeType = "application/octet-stream"
    const attachmentBytes = "phase-d step-21 sentinel 32-byte"
      ## 32 ASCII octets — clean JSON round-trip.
    doAssert attachmentBytes.len == 32, "test sentinel must be exactly 32 bytes"

    let seededId = seedMixedEmail(
        client, mailAccountId, inbox, "phase-d step-21 attachment",
        "Body precedes the attachment.", attachmentName, attachmentMimeType,
        attachmentBytes, "seedMixed",
      )
      .expect("seedMixedEmail")

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "attachments"]),
    )
    let resp = client.send(b).expect("send Email/get attachments")
    captureIfRequested(client, "email-multipart-mixed-attachment-stalwart").expect(
      "captureIfRequested"
    )
    let getResp = resp.get(getHandle).expect("Email/get attachments extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"

    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.attachments.len == 1,
      "expected one attachment, got " & $email.attachments.len
    let attachment = email.attachments[0]
    doAssert attachment.isLeaf, "attachments[0] must be a leaf"
    doAssert attachment.disposition.isSome, "attachments[0].disposition must be present"
    doAssert attachment.disposition.unsafeGet.kind == cdAttachment,
      "attachments[0].disposition must be cdAttachment (got " &
        $attachment.disposition.unsafeGet.kind & ")"
    doAssert attachment.name.isSome and attachment.name.unsafeGet == attachmentName,
      "attachments[0].name must be the injected filename"
    doAssert string(attachment.blobId).len > 0,
      "attachments[0].blobId must be non-empty"
    doAssert attachment.size == UnsignedInt(32),
      "attachments[0].size must be 32 (got " & $attachment.size & ")"
    client.close()
