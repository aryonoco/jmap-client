# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``setNotFound`` per-item
## /set rejection (``tests/testdata/captured/
## set-error-not-found-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms: returns ``"notFound"`` rawType in
## ``notDestroyed`` when a destroy targets a non-existent record.
## Verifies the wire shape parses through ``SetResponse[T]`` and the
## ``destroyResults`` table carries the typed ``SetError`` on the
## error rail.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedSetErrorNotFound:
  let j = loadCapturedFixture("set-error-not-found-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/set",
    "successful Email/set with notDestroyed must surface as Email/set, got " &
      inv.rawName
  let setResp =
    SetResponse[EmailCreatedItem].fromJson(inv.arguments).expect("SetResponse.fromJson")
  let syntheticId = Id("zzzzz")
  var found = false
  setResp.destroyResults.withValue(syntheticId, outcome):
    doAssert outcome.isErr, "synthetic id outcome must be Err(SetError)"
    let se = outcome.error
    doAssert se.rawType == "notFound",
      "Stalwart returns canonical 'notFound' rawType, got " & se.rawType
    doAssert se.errorType == setNotFound,
      "errorType must project to setNotFound, got " & $se.errorType
    doAssert se.errorType == parseSetErrorType(se.rawType),
      "errorType / rawType must be derived consistently"
    found = true
  do:
    doAssert false, "destroyResults must contain the synthetic id"
  doAssert found
