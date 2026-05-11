# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Identity/set update``
## response (RFC 8621 §6.3,
## ``tests/testdata/captured/identity-set-update-stalwart.json``).
## Verifies that ``SetResponse[IdentityCreatedItem, PartialIdentity].fromJson`` lifts
## Stalwart's wire-shape ``updated[id] = null`` into a single
## ``ok(Opt.none(JsonNode))`` outcome — the merged-Result map shape
## documented in ``methods.nim``.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedIdentitySetUpdateStalwart:
  forEachCapturedServer("identity-set-update", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    # Two server-specific shapes are RFC-conformant here:
    #   * Stalwart/James implement Identity/set and emit the typed
    #     update-response shape projected by ``SetResponse[Identity-
    #     CreatedItem]``.
    #   * Cyrus 3.12.2 omits Identity/set entirely
    #     (``imap/jmap_mail.c:122-123``) and surfaces ``metUnknownMethod``
    #     — the universal client-library contract here is the typed-
    #     error projection.
    if inv.rawName == "Identity/set":
      let setResp = SetResponse[IdentityCreatedItem, PartialIdentity]
        .fromJson(inv.arguments)
        .expect("SetResponse[IdentityCreatedItem, PartialIdentity].fromJson")
      doAssert setResp.updateResults.len == 1,
        "exactly one update outcome expected (got " & $setResp.updateResults.len & ")"
      for id, outcome in setResp.updateResults.pairs:
        doAssert outcome.isOk,
          "update outcome must be Ok (got rawType=" & outcome.error.rawType & ")"
        doAssert string(id).len > 0, "updated id must be non-empty"
      doAssert setResp.newState.isSome, "newState must be present in this fixture"
    else:
      doAssert inv.rawName == "error",
        "Cyrus rejection must surface as a method-level error invocation (got " &
          inv.rawName & ")"
