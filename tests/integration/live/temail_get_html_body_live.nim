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

block temailGetHtmlBodyLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    const textBody = "phase-d step-20 plain part"
    const htmlBody = "<html><body><p>phase-d step-20 <b>html</b> part</p></body></html>"
    let seededId = seedAlternativeEmail(
        client, mailAccountId, inbox, "phase-d step-20 alternative", textBody, htmlBody,
        "seedAlt",
      )
      .expect("seedAlternativeEmail")

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "textBody", "htmlBody", "bodyValues"]),
      bodyFetchOptions = EmailBodyFetchOptions(fetchBodyValues: bvsTextAndHtml),
    )
    let resp = client.send(b).expect("send Email/get html body")
    captureIfRequested(client, "email-multipart-alternative-stalwart").expect(
      "captureIfRequested"
    )
    let getResp = resp.get(getHandle).expect("Email/get html body extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"

    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.textBody.len == 1, "expected one text/plain leaf in textBody"
    let textLeaf = email.textBody[0]
    doAssert textLeaf.isLeaf, "textBody[0] must be a leaf"
    doAssert textLeaf.contentType == "text/plain",
      "textBody[0].contentType must be text/plain (got " & textLeaf.contentType & ")"

    doAssert email.htmlBody.len == 1, "expected one text/html leaf in htmlBody"
    let htmlLeaf = email.htmlBody[0]
    doAssert htmlLeaf.isLeaf, "htmlBody[0] must be a leaf"
    doAssert htmlLeaf.contentType == "text/html",
      "htmlBody[0].contentType must be text/html (got " & htmlLeaf.contentType & ")"

    doAssert email.bodyValues.len == 2,
      "bvsTextAndHtml must yield two bodyValues entries (got " & $email.bodyValues.len &
        ")"
    doAssert textLeaf.partId in email.bodyValues,
      "bodyValues missing entry for text partId " & $textLeaf.partId
    doAssert htmlLeaf.partId in email.bodyValues,
      "bodyValues missing entry for html partId " & $htmlLeaf.partId

    let htmlValue = email.bodyValues[htmlLeaf.partId]
    doAssert htmlValue.value == htmlBody,
      "html bodyValue.value must round-trip the injected string verbatim"
    client.close()
