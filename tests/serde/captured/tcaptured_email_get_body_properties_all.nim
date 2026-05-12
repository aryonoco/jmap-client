# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## under ``bodyProperties`` + ``bvsAll``
## (``tests/testdata/captured/email-get-body-properties-all-stalwart.json``).
## Verifies that ``Email.fromJson`` parses the recursive multipart
## ``bodyStructure`` tree under a narrowed bodyProperties set and
## the truncated bodyValues table that Stalwart 0.15.5 emits for
## ``bvsAll`` over a multipart/mixed corpus.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailGetBodyPropertiesAll:
  let j = loadCapturedFixture("email-get-body-properties-all-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/get"

  let getResp =
    GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
  doAssert getResp.list.len == 1, "captured Email/get must carry one record"
  let email = getResp.list[0]
  doAssert email.bodyStructure.isSome,
    "bodyStructure must be present when explicitly requested"
  let bs = email.bodyStructure.unsafeGet
  doAssert bs.isMultipart,
    "multipart/mixed seed must produce a multipart bodyStructure root"
  doAssert bs.subParts.len >= 2,
    "multipart/mixed seed must carry at least two subParts (text + attachment)"
  doAssert email.bodyValues.len >= 1, "bvsAll must yield at least one bodyValues entry"
  for partId, bv in email.bodyValues.pairs:
    doAssert string(partId).len > 0, "every bodyValues key must be non-empty"
    doAssert bv.value.len > 0, "bvsAll-emitted bodyValue must carry decoded content"
