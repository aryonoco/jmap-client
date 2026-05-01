# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## with typed-header properties (RFC 8621 §4.1.2 / §4.2,
## ``tests/testdata/captured/email-header-forms-stalwart.json``).
## Three dynamic header keys parse through ``parseHeaderValue`` to
## the expected ``HeaderForm`` discriminator with populated payload.

{.push raises: [].}

import std/json

import jmap_client
import ./mloader

block tcapturedEmailHeaderForms:
  let j = loadCapturedFixture("email-header-forms-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/get"

  let listNode = inv.arguments{"list"}
  doAssert not listNode.isNil and listNode.kind == JArray and listNode.len == 1
  let entity = listNode[0]

  let listPostNode = entity{"header:List-Post:asURLs"}
  doAssert not listPostNode.isNil
  let listPostHV =
    parseHeaderValue(hfUrls, listPostNode).expect("parseHeaderValue List-Post")
  doAssert listPostHV.form == hfUrls
  doAssert listPostHV.urls.isSome and listPostHV.urls.unsafeGet.len >= 1,
    "List-Post must carry at least one URL in the captured fixture"

  let dateNode = entity{"header:Date:asDate"}
  doAssert not dateNode.isNil
  let dateHV = parseHeaderValue(hfDate, dateNode).expect("parseHeaderValue Date")
  doAssert dateHV.form == hfDate
  doAssert dateHV.date.isSome,
    "Date must parse to a populated date in the captured fixture"

  let fromNode = entity{"header:From:asAddresses"}
  doAssert not fromNode.isNil
  let fromHV = parseHeaderValue(hfAddresses, fromNode).expect("parseHeaderValue From")
  doAssert fromHV.form == hfAddresses
  doAssert fromHV.addresses.len >= 1,
    "From must carry at least one address in the captured fixture"
