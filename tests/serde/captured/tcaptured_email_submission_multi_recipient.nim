# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured multi-recipient
## ``EmailSubmission/get`` response (RFC 8621 §7.4 ¶8,
## ``tests/testdata/captured/email-submission-multi-recipient-delivery-stalwart.json``).
## First captured fixture with ``len(deliveryStatus) > 1`` — the
## ``DeliveryStatusMap`` deserialiser had only been wire-tested on
## single-recipient payloads through Phase F. Two-recipient envelope
## ``alice → [bob, alice-self]`` produces two map entries, one per
## RFC 5321 ``rcptTo`` address.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailSubmissionMultiRecipient:
  let j = loadCapturedFixture("email-submission-multi-recipient-delivery-stalwart")
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
  doAssert dsMap.len == 2,
    "two-recipient envelope must produce two deliveryStatus entries (got " & $dsMap.len &
      ")"

  let bobMailbox =
    parseRFC5321Mailbox("bob@example.com").expect("parseRFC5321Mailbox bob")
  let aliceMailbox =
    parseRFC5321Mailbox("alice@example.com").expect("parseRFC5321Mailbox alice")
  doAssert bobMailbox in dsMap,
    "deliveryStatus must carry an entry keyed by bob@example.com"
  doAssert aliceMailbox in dsMap,
    "deliveryStatus must carry an entry keyed by alice@example.com"
  doAssert dsMap[bobMailbox].smtpReply.replyCode == ReplyCode(250),
    "bob's reply code must be 250 (got " & $dsMap[bobMailbox].smtpReply.replyCode & ")"
  doAssert dsMap[aliceMailbox].smtpReply.replyCode == ReplyCode(250),
    "alice-self's reply code must be 250 (got " &
      $dsMap[aliceMailbox].smtpReply.replyCode & ")"
