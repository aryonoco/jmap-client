# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## carrying the read-back of an ``Email/import``-ed message
## (``tests/testdata/captured/
## postels-law-receive-adversarial-mime-stalwart.json``).
##
## Verifies the lenient receive parsers project Stalwart's
## projection of an imported message through ``Email.fromJson``
## without error.  The Phase J Step 73 live test exercised the full
## seed-via-forward + import + readback chain; this replay pins
## Stalwart's empirical Email shape so a future regression breaks
## the parser-only test as well.

{.push raises: [].}

import std/json
import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedPostelsLawReceive:
  let j = loadCapturedFixture("postels-law-receive-adversarial-mime-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/get"
  let getResp =
    GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
  doAssert getResp.list.len == 1
  let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson lenient")
  doAssert email.id.isSome
  doAssert email.fromAddr.isSome and email.fromAddr.unsafeGet.len >= 1
  doAssert email.subject.isSome
  doAssert email.receivedAt.isSome

  # Empty-vs-null parser tolerance — keywords on an imported
  # message may be empty.  Whatever shape Stalwart emits, the
  # parser projects keywords into ``Table[Keyword, bool]``.
  let kwNode = getResp.list[0]{"keywords"}
  if not kwNode.isNil:
    doAssert kwNode.kind in {JObject, JNull},
      "keywords wire shape must be JObject or JNull; got " & $kwNode.kind
