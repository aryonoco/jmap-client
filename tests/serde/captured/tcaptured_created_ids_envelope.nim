# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``createdIds`` envelope
## round-trip (``tests/testdata/captured/
## created-ids-envelope-stalwart.json``).
##
## Stalwart 0.15.5 RFC-conforms (RFC 8620 §3.3): when the client
## sends ``createdIds`` in the request, the server echoes the same
## map verbatim in the response.  Verifies (a) ``Response.fromJson``
## projects ``createdIds`` into ``Opt[Table[CreationId, Id]]``;
## (b) the seeded entry ``knownEmail → <id>`` round-trips; (c)
## ``Response.toJson`` re-emits the field structurally.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader
import ../../mtestblock

testCase tcapturedCreatedIdsEnvelope:
  let j = loadCapturedFixture("created-ids-envelope-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  doAssert resp.methodResponses[0].rawName == "Core/echo"
  doAssert resp.createdIds.isSome,
    "Stalwart MUST echo createdIds when client sent them (RFC 8620 §3.3)"
  var echoed = resp.createdIds.unsafeGet
  doAssert echoed.len == 1, "fixture carries one createdIds entry"
  let knownCid = parseCreationId("knownEmail").expect("parseCreationId")
  echoed.withValue(knownCid, v):
    # The specific Id value is Stalwart-state-dependent (it counts
    # email creations from server start) and drifts whenever the
    # fixture is re-captured. The RFC 8620 §3.3 contract is that the
    # cid resolves to *some* Id structurally; pinning the empirical
    # value would make the test fail on every re-capture without
    # gaining any contract coverage.
    doAssert v[].len > 0,
      "echoed createdIds entry must resolve to a non-empty Id; got '" & $v[] & "'"
  do:
    doAssert false, "echoed createdIds must contain the knownEmail cid"

  # Round-trip integrity: re-emit the parsed Response and re-parse;
  # the createdIds entry must survive structurally.
  let rt = envelope.Response.fromJson(resp.toJson()).expect("Response round-trip")
  doAssert rt.createdIds.isSome
