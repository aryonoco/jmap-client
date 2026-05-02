# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## with a multipart/mixed MIME tree carrying one attachment
## (``tests/testdata/captured/email-multipart-mixed-attachment-stalwart.json``).
## Verifies that the attachment leaf carries
## ``disposition = cdAttachment``, the injected filename, and a
## non-empty ``BlobId`` — the contract Step 24 relies on for
## ``Email/parse``.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailMultipartMixedAttachment:
  let j = loadCapturedFixture("email-multipart-mixed-attachment-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/get"

  let getResp =
    GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
  doAssert getResp.list.len == 1
  let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
  doAssert email.attachments.len == 1,
    "multipart/mixed seed exposes one attachment leaf"

  let attachment = email.attachments[0]
  doAssert attachment.isLeaf, "attachment must be a leaf"
  doAssert attachment.disposition.isSome, "attachment must carry a disposition"
  doAssert attachment.disposition.unsafeGet.kind == cdAttachment,
    "disposition must project as cdAttachment"
  doAssert attachment.name.isSome,
    "attachment must carry a filename in the captured fixture"
  doAssert string(attachment.blobId).len > 0,
    "attachment.blobId must be non-empty for Email/parse reuse"
  doAssert attachment.size == UnsignedInt(32),
    "captured sentinel is exactly 32 bytes (got " & $attachment.size & ")"
