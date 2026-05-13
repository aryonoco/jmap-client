# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/get with ``bodyValueScope = bvsText``
## (RFC 8621 §4.2 / §4.1.4) against Stalwart. Phase D Step 19 — the
## entry point into the body-content suite. Asserts the structural
## shape of ``textBody`` and ``bodyValues`` for a freshly seeded
## text/plain message:
##
##   1. ``textBody.len == 1`` — one text/plain leaf, no html or
##      attachment siblings.
##   2. ``textBody[0]`` parses as a leaf ``EmailBodyPart``,
##      ``contentType == "text/plain"``, ``size > 0`` (parser is
##      byte-passthrough; the exact octet count is server-dependent so
##      a range assertion is the right granularity).
##   3. ``textBody[0].charset.unsafeGet.toLowerAscii == "utf-8"``.
##      ``serde_body.parseCharsetField`` is byte-passthrough; the
##      ``.toLowerAscii`` guards against benign capitalisation drift.
##   4. ``bodyValues.len == 1`` — exactly the text leaf was fetched.
##      ``serde_email.parseBodyValues`` collapses absent / null /
##      empty-object identically.
##
## ``Email/get`` is issued with ``properties = Opt.some(@["id",
## "textBody", "bodyValues"])`` so the response is a partial Email.
## ``Email.fromJson`` parses the sparse shape because every metadata
## field is ``Opt[T]`` post-refactor.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``.

import std/strutils
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailGetTextBodyLive:
  forEachLiveTarget(target):
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
    let seededId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-d step-19 text body", "seedTextBody"
      )
      .expect("seedSimpleEmail[" & $target.kind & "]")

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "textBody", "bodyValues"]),
      bodyFetchOptions = EmailBodyFetchOptions(fetchBodyValues: bvsText),
    )
    let resp =
      client.send(b.freeze()).expect("send Email/get text body[" & $target.kind & "]")
    let getResp =
      resp.get(getHandle).expect("Email/get text body extract[" & $target.kind & "]")
    assertOn target, getResp.list.len == 1, "Email/get must return the seeded message"

    let email = getResp.list[0]
    assertOn target,
      email.textBody.len == 1,
      "expected one text/plain leaf, got " & $email.textBody.len
    let textLeaf = email.textBody[0]
    assertOn target, textLeaf.isLeaf, "textBody[0] must be a leaf"
    assertOn target,
      textLeaf.contentType == "text/plain",
      "textBody[0].contentType must be text/plain (got " & textLeaf.contentType & ")"
    assertOn target,
      textLeaf.size > parseUnsignedInt(0).get(),
      "textBody[0].size must be > 0 (got " & $textLeaf.size & ")"
    assertOn target,
      textLeaf.charset.isSome, "textBody[0].charset must be present for a text/* leaf"
    # The seeded body is pure 7-bit ASCII. RFC 2046 §4.1.2 permits
    # ``us-ascii`` (Cyrus 3.12.2) and ``utf-8`` (Stalwart, James) to
    # describe the same payload. The library's contract is that the
    # ``charset`` parses to a non-empty ``Opt.some(string)``; the
    # specific charset label is server-discretionary.
    assertOn target,
      textLeaf.charset.unsafeGet.toLowerAscii in ["utf-8", "us-ascii"],
      "textBody[0].charset must be utf-8 or us-ascii case-insensitive (got " &
        textLeaf.charset.unsafeGet & ")"

    assertOn target,
      email.bodyValues.len == 1,
      "bvsText must yield exactly one bodyValues entry (got " & $email.bodyValues.len &
        ")"
