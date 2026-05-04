# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/parse (RFC 8621 §4.9) against
## Stalwart. Phase D Step 24 — exercises the full
## ``EmailParseResponse`` extraction path on a message/rfc822 blob
## attached to a freshly seeded email.
##
## Wire flow:
##   1. ``mlive.seedForwardedEmail`` creates a multipart/mixed email
##      whose attachment is a ``message/rfc822`` payload built from
##      an inner subject / from / body.
##   2. ``Email/get`` with ``properties = [id, attachments]`` fetches
##      the outer envelope so the attachment's ``BlobId`` is
##      available.
##   3. ``Email/parse`` is issued against that blob id with
##      ``properties = [bodyStructure, subject, from]`` so the
##      response satisfies ``parsedEmailFromJson``'s required
##      ``bodyStructure`` field while still narrowing the surface
##      area.
##   4. The typed-overload ``EmailParseResponse.fromJson`` (added in
##      D0.5) resolves through the ``resp.get(handle)`` mixin path.
##
## Asserts:
##   1. ``parsedResponse.parsed`` carries one entry, keyed by the
##      attachment's blobId.
##   2. The parsed inner email's ``subject == innerSubject``.
##   3. The parsed inner email's ``fromAddr[0].email ==
##      innerFrom.email``.
##
## Captures: ``email-parse-rfc822-stalwart`` after the ``Email/parse``
## send so the parsed-blob wire shape feeds the parser-only replay.
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

block temailParseLive:
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
    const innerSubject = "phase-d step-24 inner subject"
    const innerEmail = "bob@example.com"
    const innerName = "Bob"
    const innerBody = "phase-d step-24 inner body line."
    let innerFrom = parseEmailAddress(innerEmail, Opt.some(innerName)).expect(
        "parseEmailAddress innerFrom"
      )
    let outerId = seedForwardedEmail(
        client, mailAccountId, inbox, "phase-d step-24 forward", innerSubject,
        innerFrom, innerBody, "seedForward",
      )
      .expect("seedForwardedEmail")

    let (bGet, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[outerId]),
      properties = Opt.some(@["id", "attachments"]),
    )
    let getRespOuter = client.send(bGet).expect("send Email/get attachments")
    let getResp = getRespOuter.get(getHandle).expect("Email/get attachments extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"

    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.attachments.len == 1, "expected exactly one attachment"
    let attachment = email.attachments[0]
    doAssert attachment.contentType == "message/rfc822",
      "attachment must be message/rfc822 (got " & attachment.contentType & ")"
    let blobId = attachment.blobId
    doAssert string(blobId).len > 0, "attachment blobId must be non-empty"

    let (bParse, parseHandle) = addEmailParse(
      initRequestBuilder(),
      mailAccountId,
      blobIds = @[blobId],
      properties = Opt.some(@["bodyStructure", "subject", "from"]),
    )
    let parseRespOuter = client.send(bParse).expect("send Email/parse")
    captureIfRequested(client, "email-parse-rfc822-stalwart").expect(
      "captureIfRequested"
    )
    let parseResp = parseRespOuter.get(parseHandle).expect("Email/parse extract")
    doAssert parseResp.parsed.len == 1,
      "Email/parse must return one parsed entry (got " & $parseResp.parsed.len & ")"
    parseResp.parsed.withValue(blobId, parsed):
      doAssert parsed.subject.isSome,
        "parsed inner email must carry the inner Subject header"
      doAssert parsed.subject.unsafeGet == innerSubject,
        "parsed.subject must equal innerSubject (got " & parsed.subject.unsafeGet & ")"
      doAssert parsed.fromAddr.isSome,
        "parsed inner email must carry the inner From header"
      let fromList = parsed.fromAddr.unsafeGet
      doAssert fromList.len == 1,
        "parsed.fromAddr must contain one entry (got " & $fromList.len & ")"
      doAssert fromList[0].email == innerEmail,
        "parsed.fromAddr[0].email must equal innerEmail (got " & fromList[0].email & ")"
    do:
      doAssert false, "parsed map must contain entry for the requested blobId"
    client.close()
