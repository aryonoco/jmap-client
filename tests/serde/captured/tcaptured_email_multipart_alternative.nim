# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## with a multipart/alternative MIME tree
## (``tests/testdata/captured/email-multipart-alternative-stalwart.json``).
## Verifies that a partial Email body shape (``properties = [id,
## textBody, htmlBody, bodyValues]``) parses field-by-field via
## ``EmailBodyPart.fromJson`` / ``EmailBodyValue.fromJson``.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailMultipartAlternative:
  forEachCapturedServer("email-multipart-alternative", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/get"

    let getResp =
      GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
    doAssert getResp.list.len == 1, "Email/get list must carry exactly one entity"

    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.textBody.len == 1, "alternative tree exposes one text/plain leaf"
    doAssert email.textBody[0].contentType == "text/plain"
    doAssert email.htmlBody.len == 1, "alternative tree exposes one text/html leaf"
    doAssert email.htmlBody[0].contentType == "text/html"
    doAssert email.bodyValues.len == 2,
      "bvsTextAndHtml must yield two bodyValues entries"
    let textValue = email.bodyValues[email.textBody[0].partId]
    doAssert textValue.value.len > 0, "text bodyValue must carry decoded content"
    let htmlValue = email.bodyValues[email.htmlBody[0].partId]
    doAssert htmlValue.value.len > 0, "html bodyValue must carry decoded content"
