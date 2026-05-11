# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured deep-path PatchObject
## rejection (``tests/testdata/captured/
## patch-object-deep-paths-stalwart.json``).  Stalwart 0.15.5
## collapses deep-path PatchObject expressions
## (``replyTo/0/name``) onto ``invalidProperties`` rather than
## ``invalidPatch`` (RFC 8620 §5.3 mandates ``invalidPatch`` for
## unknown-property paths).  After Phase K0 made
## ``SetResponse.newState`` ``Opt[JmapState]``, the typed parser
## projects the rejection rail directly via
## ``SetResponse[IdentityCreatedItem].fromJson`` →
## ``updateResults``.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedPatchObjectDeepPaths:
  let j = loadCapturedFixture("patch-object-deep-paths-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Identity/set",
    "deep-path patch must surface as Identity/set with notUpdated; got " & inv.rawName
  let setResp = SetResponse[IdentityCreatedItem].fromJson(inv.arguments).expect(
      "SetResponse[IdentityCreatedItem].fromJson"
    )
  doAssert setResp.newState.isNone,
    "fixture pins Stalwart's missing-newState wire shape"
  doAssert setResp.updateResults.len == 1, "exactly one notUpdated entry expected"
  for id, outcome in setResp.updateResults.pairs:
    doAssert outcome.isErr, "deep-path entry must be Err(SetError)"
    let se = outcome.error
    doAssert se.rawType == "invalidProperties",
      "Stalwart projects deep-path rejection as invalidProperties; got " & se.rawType
    doAssert se.errorType == setInvalidProperties,
      "errorType must project to setInvalidProperties; got " & $se.errorType
    doAssert se.properties == @["replyTo/0/name"],
      "Stalwart echoes the offending deep path; got " & $se.properties
    doAssert se.description.isSome,
      "Stalwart populates description on deep-path rejection"
    doAssert se.description.unsafeGet == "Field could not be set.",
      "Stalwart's description string on deep-path rejection"
