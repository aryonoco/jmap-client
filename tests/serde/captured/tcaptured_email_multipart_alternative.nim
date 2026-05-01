# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## with a multipart/alternative MIME tree
## (``tests/testdata/captured/email-multipart-alternative-stalwart.json``).
## Verifies that a partial Email body shape (``properties = [id,
## textBody, htmlBody, bodyValues]``) parses field-by-field via
## ``EmailBodyPart.fromJson`` / ``EmailBodyValue.fromJson``.

{.push raises: [].}

import std/json

import jmap_client
import ./mloader

block tcapturedEmailMultipartAlternative:
  let j = loadCapturedFixture("email-multipart-alternative-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/get"

  let listNode = inv.arguments{"list"}
  doAssert not listNode.isNil and listNode.kind == JArray and listNode.len == 1,
    "Email/get list must carry exactly one entity"
  let entity = listNode[0]

  let textBodyNode = entity{"textBody"}
  doAssert not textBodyNode.isNil and textBodyNode.kind == JArray and
    textBodyNode.len == 1, "alternative tree exposes one text/plain leaf"
  let textLeaf = EmailBodyPart.fromJson(textBodyNode[0]).expect("text leaf parse")
  doAssert textLeaf.contentType == "text/plain"

  let htmlBodyNode = entity{"htmlBody"}
  doAssert not htmlBodyNode.isNil and htmlBodyNode.kind == JArray and
    htmlBodyNode.len == 1, "alternative tree exposes one text/html leaf"
  let htmlLeaf = EmailBodyPart.fromJson(htmlBodyNode[0]).expect("html leaf parse")
  doAssert htmlLeaf.contentType == "text/html"

  let bvNode = entity{"bodyValues"}
  doAssert not bvNode.isNil and bvNode.kind == JObject and bvNode.len == 2,
    "bvsTextAndHtml must yield two bodyValues entries"
  let textValue =
    EmailBodyValue.fromJson(bvNode[$textLeaf.partId]).expect("text value parse")
  doAssert textValue.value.len > 0, "text bodyValue must carry decoded content"
  let htmlValue =
    EmailBodyValue.fromJson(bvNode[$htmlLeaf.partId]).expect("html value parse")
  doAssert htmlValue.value.len > 0, "html bodyValue must carry decoded content"
