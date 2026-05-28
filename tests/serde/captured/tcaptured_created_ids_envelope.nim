# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``createdIds`` envelope
## across all three reference servers
## (``tests/testdata/captured/created-ids-envelope-{stalwart,james,cyrus}.json``).
##
## Per RFC 8620 §3.3, when the client sends ``createdIds`` in the
## request, the server SHOULD echo the same map in the response.
## Stalwart 0.15.5 and Cyrus 3.12.2 conform; Apache James 3.9 omits
## the field. The test verifies (a) ``Response.fromJson`` projects
## the captured wire shape into the typed Response surface;
## (b) when ``createdIds`` IS present, the seeded entry
## ``knownEmail → <id>`` round-trips structurally; (c) two parses
## of the same fixture yield equal values (replaces the previous
## ``toJson`` round-trip, which is gone after A16: ``Response.toJson``
## is deleted).

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedCreatedIdsEnvelope:
  forEachCapturedServer("created-ids-envelope", fixture):
    let resp1 = envelope.Response.fromJson(fixture).expect(
        "envelope.Response.fromJson (first parse)"
      )
    let resp2 = envelope.Response.fromJson(fixture).expect(
        "envelope.Response.fromJson (second parse)"
      )
    doAssert resp1 == resp2,
      "two parses of the same captured Response must yield equal values"

    doAssert resp1.methodResponses.len == 1
    doAssert resp1.methodResponses[0].rawName == "Core/echo"

    # Per-server divergence: Stalwart 0.15.5 and Cyrus 3.12.2 echo
    # ``createdIds`` per RFC 8620 §3.3; Apache James 3.9 omits it.
    # When present, the seeded ``knownEmail`` entry must round-trip
    # structurally to a non-empty Id.
    if resp1.createdIds.isSome:
      var echoed = resp1.createdIds.unsafeGet
      doAssert echoed.len == 1, "fixture carries one createdIds entry"
      let knownCid = parseCreationId("knownEmail").expect("parseCreationId")
      echoed.withValue(knownCid, v):
        doAssert v[].len > 0,
          "echoed createdIds entry must resolve to a non-empty Id; got '" & $v[] & "'"
      do:
        doAssert false, "echoed createdIds must contain the knownEmail cid"
