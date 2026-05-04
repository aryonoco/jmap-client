# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Identity/set update``
## response (RFC 8621 §6.3,
## ``tests/testdata/captured/identity-set-update-stalwart.json``).
## Verifies that ``SetResponse[IdentityCreatedItem].fromJson`` lifts
## Stalwart's wire-shape ``updated[id] = null`` into a single
## ``ok(Opt.none(JsonNode))`` outcome — the merged-Result map shape
## documented in ``methods.nim``.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedIdentitySetUpdateStalwart:
  forEachCapturedServer("identity-set-update", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Identity/set", "expected Identity/set, got " & inv.rawName
    let setResp = SetResponse[IdentityCreatedItem].fromJson(inv.arguments).expect(
        "SetResponse[IdentityCreatedItem].fromJson"
      )
    doAssert setResp.updateResults.len == 1,
      "exactly one update outcome expected (got " & $setResp.updateResults.len & ")"
    for id, outcome in setResp.updateResults.pairs:
      doAssert outcome.isOk,
        "update outcome must be Ok (got rawType=" & outcome.error.rawType & ")"
      doAssert string(id).len > 0, "updated id must be non-empty"
    doAssert setResp.newState.isSome, "newState must be present in this fixture"
