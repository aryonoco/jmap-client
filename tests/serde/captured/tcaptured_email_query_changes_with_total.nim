# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/queryChanges``
## response with ``calculateTotal: true``
## (``tests/testdata/captured/email-query-changes-with-total-stalwart.json``).
## Verifies the ``AddedItem {id, index}`` array shape and the
## ``total`` field that RFC 8620 §5.6 emits when the request opts in.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailQueryChangesWithTotal:
  let j = loadCapturedFixture("email-query-changes-with-total-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/queryChanges"

  let qcr = QueryChangesResponse[Email].fromJson(inv.arguments).expect(
      "QueryChangesResponse[Email].fromJson"
    )
  doAssert ($qcr.oldQueryState).len > 0, "oldQueryState must be non-empty"
  doAssert ($qcr.newQueryState).len > 0, "newQueryState must be non-empty"
  doAssert qcr.total.isSome,
    "total must be present when calculateTotal=true was requested"
  doAssert qcr.added.len >= 1,
    "at least one AddedItem expected (got " & $qcr.added.len & ")"
  for item in qcr.added:
    doAssert string(item.id).len > 0, "added.id must be non-empty"
