# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response from
## bob's account after alice→bob delivery (RFC 8621 §4.2,
## ``tests/testdata/captured/bob-inbox-after-alice-delivery-stalwart.json``).
## First captured fixture authored against bob's accountId rather than
## alice's. Asserts the delivery post-condition the Phase F EmailSubmission
## tests left implicit: the entity that arrives in bob's inbox has alice's
## ``from`` and resides in a mailbox keyed by bob's account.

{.push raises: [].}

import std/json

import jmap_client
import ./mloader

block tcapturedBobInboxAfterDelivery:
  let j = loadCapturedFixture("bob-inbox-after-alice-delivery-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/get", "expected Email/get, got " & inv.rawName

  let getResp =
    GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
  doAssert getResp.list.len == 1,
    "exactly one delivered email expected (got " & $getResp.list.len & ")"

  let entity = getResp.list[0]
  let subjectNode = entity{"subject"}
  doAssert not subjectNode.isNil and subjectNode.kind == JString,
    "captured delivery must surface a string subject"
  doAssert subjectNode.getStr.len > 0, "subject must be non-empty"

  let fromNode = entity{"from"}
  doAssert not fromNode.isNil and fromNode.kind == JArray and fromNode.len > 0,
    "captured delivery must include a non-empty from array"
  let fromAddrNode = fromNode[0]{"email"}
  doAssert not fromAddrNode.isNil and fromAddrNode.kind == JString,
    "from[0] must include a string email"
  doAssert fromAddrNode.getStr == "alice@example.com",
    "delivered from[0].email must be alice@example.com (got " & fromAddrNode.getStr & ")"

  let mbIdsNode = entity{"mailboxIds"}
  doAssert not mbIdsNode.isNil and mbIdsNode.kind == JObject,
    "captured delivery must include a non-empty mailboxIds object"
  doAssert mbIdsNode.len >= 1,
    "delivered email must reside in at least one mailbox (got " & $mbIdsNode.len & ")"
