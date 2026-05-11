# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``setInvalidProperties``
## per-item /set rejection (``tests/testdata/captured/
## set-error-invalid-properties-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms: returns ``"invalidProperties"``
## rawType when a create attempts to set a server-assigned immutable
## property (``id``).  The ``properties`` array carries the offending
## property names per RFC 8620 §5.3 SHOULD.  Verifies the typed
## ``SetError.properties`` payload arm deserialises correctly.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedSetErrorInvalidProperties:
  let j = loadCapturedFixture("set-error-invalid-properties-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/set",
    "Email/set with notCreated must surface as Email/set, got " & inv.rawName
  let setResp = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(inv.arguments)
    .expect("SetResponse.fromJson")
  let cidLabel = parseCreationId("phaseJ63").expect("parseCreationId")
  var found = false
  setResp.createResults.withValue(cidLabel, outcome):
    doAssert outcome.isErr, "create outcome must be Err(SetError)"
    let se = outcome.error
    doAssert se.rawType == "invalidProperties",
      "Stalwart returns canonical 'invalidProperties' rawType, got " & se.rawType
    doAssert se.errorType == setInvalidProperties,
      "errorType must project to setInvalidProperties, got " & $se.errorType
    doAssert se.errorType == parseSetErrorType(se.rawType),
      "errorType / rawType must be derived consistently"
    doAssert se.properties == @["id"],
      "Stalwart echoes the offending immutable-property name; got " & $se.properties
    found = true
  do:
    doAssert false, "createResults must contain the create label"
  doAssert found
