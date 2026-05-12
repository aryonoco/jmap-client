# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/get with ``bodyValueScope =
## bvsTextAndHtml`` (RFC 8621 §4.2 / §4.1.4) against Stalwart. Phase D
## Step 20 — exercises the multipart/alternative MIME tree on a
## seeded email built via ``mlive.seedAlternativeEmail``.
##
## Asserts:
##   1. ``textBody.len == 1`` and ``htmlBody.len == 1`` — RFC 8621
##      §4.1.4 picks one preferred leaf per type from the alternative
##      branch.
##   2. ``textBody[0].contentType == "text/plain"`` and
##      ``htmlBody[0].contentType == "text/html"``.
##   3. ``bodyValues`` has exactly two entries — one per fetched leaf.
##      The map is keyed by ``partId``; the keys must include both
##      ``textBody[0].partId`` and ``htmlBody[0].partId``.
##   4. The decoded value of the html leaf matches the injected string
##      verbatim (byte-equality on the UTF-8 octets sent through
##      ``Email/set create``).
##
## Captures: ``email-multipart-alternative-stalwart`` after the
## ``Email/get`` so the multipart MIME tree shape is recorded for the
## parser-only replay.
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
import ../../mtestblock

testCase temailGetHtmlBodyLive:
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
    const textBody = "phase-d step-20 plain part"
    const htmlBody = "<html><body><p>phase-d step-20 <b>html</b> part</p></body></html>"
    let seededId = seedAlternativeEmail(
        client, mailAccountId, inbox, "phase-d step-20 alternative", textBody, htmlBody,
        "seedAlt",
      )
      .expect("seedAlternativeEmail[" & $target.kind & "]")

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "textBody", "htmlBody", "bodyValues"]),
      bodyFetchOptions = EmailBodyFetchOptions(fetchBodyValues: bvsTextAndHtml),
    )
    let resp =
      client.send(b.freeze()).expect("send Email/get html body[" & $target.kind & "]")
    captureIfRequested(client, "email-multipart-alternative-" & $target.kind).expect(
      "captureIfRequested"
    )
    let getResp =
      resp.get(getHandle).expect("Email/get html body extract[" & $target.kind & "]")
    assertOn target, getResp.list.len == 1, "Email/get must return the seeded message"

    let email = getResp.list[0]
    assertOn target, email.textBody.len == 1, "expected one text/plain leaf in textBody"
    let textLeaf = email.textBody[0]
    assertOn target, textLeaf.isLeaf, "textBody[0] must be a leaf"
    assertOn target,
      textLeaf.contentType == "text/plain",
      "textBody[0].contentType must be text/plain (got " & textLeaf.contentType & ")"

    assertOn target, email.htmlBody.len == 1, "expected one text/html leaf in htmlBody"
    let htmlLeaf = email.htmlBody[0]
    assertOn target, htmlLeaf.isLeaf, "htmlBody[0] must be a leaf"
    assertOn target,
      htmlLeaf.contentType == "text/html",
      "htmlBody[0].contentType must be text/html (got " & htmlLeaf.contentType & ")"

    assertOn target,
      email.bodyValues.len == 2,
      "bvsTextAndHtml must yield two bodyValues entries (got " & $email.bodyValues.len &
        ")"
    assertOn target,
      textLeaf.partId in email.bodyValues,
      "bodyValues missing entry for text partId " & $textLeaf.partId
    assertOn target,
      htmlLeaf.partId in email.bodyValues,
      "bodyValues missing entry for html partId " & $htmlLeaf.partId

    let htmlValue = email.bodyValues[htmlLeaf.partId]
    assertOn target,
      htmlValue.value == htmlBody,
      "html bodyValue.value must round-trip the injected string verbatim"
    client.close()
