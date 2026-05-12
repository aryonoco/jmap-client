# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Identity/set`` response
## with all five update arms applied in one batch
## (``tests/testdata/captured/identity-changes-with-updates-stalwart.json``).
## Verifies that ``SetResponse[IdentityCreatedItem, PartialIdentity]`` parses the
## ``updated`` table where the identity id maps to ``null``
## (RFC 8620 §5.3 — server-defined fields unchanged).

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedIdentityChangesWithUpdates:
  let j = loadCapturedFixture("identity-changes-with-updates-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Identity/set"

  let setResp = SetResponse[IdentityCreatedItem, PartialIdentity]
    .fromJson(inv.arguments)
    .expect("SetResponse[IdentityCreatedItem, PartialIdentity].fromJson")
  doAssert setResp.newState.isSome, "newState must be present in this fixture"
  doAssert setResp.updateResults.len >= 1,
    "Identity/set must report at least one update outcome (got " &
      $setResp.updateResults.len & ")"
  for id, outcome in setResp.updateResults.pairs:
    doAssert string(id).len > 0, "every updated id must be non-empty"
    doAssert outcome.isOk,
      "Identity/set five-arm update must succeed for the captured identity id"
