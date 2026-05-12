# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/queryChanges``
## response with ``upToId`` parameter on the request
## (``tests/testdata/captured/email-querychanges-up-to-id-stalwart.json``).
##
## Verifies the typed ``QueryChangesResponse[Email]`` parser handles
## the wire shape produced when ``upToId`` constrains the changes
## window.  Stalwart 0.15.5 RFC-conforms.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailQueryChangesUpToId:
  let j = loadCapturedFixture("email-querychanges-up-to-id-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/queryChanges",
    "fixture is the upToId Email/queryChanges leg; got " & inv.rawName
  let qcResp = QueryChangesResponse[Email].fromJson(inv.arguments).expect(
      "QueryChangesResponse[Email].fromJson"
    )
  doAssert ($qcResp.oldQueryState).len > 0, "oldQueryState must be populated"
  doAssert ($qcResp.newQueryState).len > 0, "newQueryState must be populated"
