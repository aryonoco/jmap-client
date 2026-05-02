# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``EmailSubmission/get``
## post-delivery response (RFC 8621 §7 ¶8,
## ``tests/testdata/captured/email-submission-get-delivery-status-stalwart.json``).
## Drives the full lift chain: ``GetResponse`` → ``AnyEmailSubmission``
## → ``asFinal`` → ``DeliveryStatusMap`` → ``RFC5321Mailbox`` key →
## ``ParsedSmtpReply``. Validates that Stalwart's ``"250 2.1.5 Queued"``
## SMTP reply parses as ``replyCode == 250`` with the RFC 3463 enhanced
## triple ``2.1.5`` recovered.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailSubmissionGetDeliveryStatusStalwart:
  let j = loadCapturedFixture("email-submission-get-delivery-status-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/get",
    "expected EmailSubmission/get, got " & inv.rawName

  let getResp = GetResponse[AnyEmailSubmission].fromJson(inv.arguments).expect(
      "GetResponse[AnyEmailSubmission].fromJson"
    )
  doAssert getResp.list.len == 1,
    "exactly one EmailSubmission expected (got " & $getResp.list.len & ")"

  let any =
    AnyEmailSubmission.fromJson(getResp.list[0]).expect("AnyEmailSubmission.fromJson")
  let finalOpt = any.asFinal()
  doAssert finalOpt.isSome,
    "captured submission has undoStatus==final; entity must project as usFinal"
  let sub = finalOpt.unsafeGet

  doAssert sub.deliveryStatus.isSome, "deliveryStatus must be populated"
  let dsMap = (Table[RFC5321Mailbox, DeliveryStatus])(sub.deliveryStatus.unsafeGet)
  let bobMailbox =
    parseRFC5321Mailbox("bob@example.com").expect("parseRFC5321Mailbox bob")
  doAssert bobMailbox in dsMap,
    "deliveryStatus must carry an entry keyed by bob@example.com"

  let entry = dsMap[bobMailbox]
  doAssert entry.smtpReply.replyCode == ReplyCode(250),
    "captured Stalwart reply code must round-trip as 250 (got " &
      $entry.smtpReply.replyCode & ")"
  doAssert entry.smtpReply.enhanced.isSome,
    "captured ``250 2.1.5 Queued`` carries an RFC 3463 enhanced triple"
  let ehs = entry.smtpReply.enhanced.unsafeGet
  doAssert ehs.klass == sccSuccess, "enhanced class must be 2 (success)"
