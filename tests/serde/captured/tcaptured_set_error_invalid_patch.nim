# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured per-item /set rejection
## Stalwart returns when an update path names an unknown property
## (``tests/testdata/captured/set-error-invalid-patch-stalwart.json``).
##
## **Stalwart 0.15.5 deviation pin.**  RFC 8620 §5.3 mandates
## ``invalidPatch`` when "the path resolves to an unknown property".
## Stalwart collapses the case onto ``invalidProperties`` with the
## offending property name carried in ``properties: [...]``.  Same
## collapse pattern as Step 61 / sub-test 4.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedSetErrorInvalidPatch:
  let j = loadCapturedFixture("set-error-invalid-patch-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/set",
    "Email/set with notUpdated must surface as Email/set, got " & inv.rawName
  let setResp = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(inv.arguments)
    .expect("SetResponse.fromJson")
  doAssert setResp.updateResults.len == 1
  for id, outcome in setResp.updateResults.pairs:
    doAssert outcome.isErr, "update outcome must be Err(SetError)"
    let se = outcome.error
    doAssert se.rawType == "invalidProperties",
      "Stalwart 0.15.5 collapses invalidPatch onto 'invalidProperties' " &
        "(RFC mandates 'invalidPatch' for unknown-property paths); got " & se.rawType
    doAssert se.errorType == setInvalidProperties,
      "errorType must project to setInvalidProperties, got " & $se.errorType
    doAssert se.errorType == parseSetErrorType(se.rawType),
      "errorType / rawType must be derived consistently"
    doAssert se.properties == @["phaseJSyntheticProperty"],
      "Stalwart echoes the offending property name; got " & $se.properties
