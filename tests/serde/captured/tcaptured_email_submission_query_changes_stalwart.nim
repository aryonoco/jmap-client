# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured
## ``EmailSubmission/queryChanges`` response with
## ``calculateTotal: true`` (RFC 8621 §7.4 / RFC 8620 §5.6,
## ``tests/testdata/captured/email-submission-query-changes-stalwart.json``).
## Verifies the typed ``QueryChangesResponse[AnyEmailSubmission]``
## shape end-to-end: oldQueryState / newQueryState round-trip,
## ``total`` populated, ``added`` carries two AddedItems with
## non-empty ids and bounded indices.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailSubmissionQueryChangesStalwart:
  let j = loadCapturedFixture("email-submission-query-changes-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1,
    "captured response must carry one invocation (got " & $resp.methodResponses.len & ")"
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/queryChanges",
    "expected EmailSubmission/queryChanges, got " & inv.rawName

  let qcr = QueryChangesResponse[AnyEmailSubmission].fromJson(inv.arguments).expect(
      "QueryChangesResponse[AnyEmailSubmission].fromJson"
    )
  doAssert ($qcr.oldQueryState).len > 0, "oldQueryState must be non-empty"
  doAssert ($qcr.newQueryState).len > 0, "newQueryState must be non-empty"
  doAssert qcr.total.isSome,
    "total must be present when calculateTotal=true was requested"
  doAssert qcr.removed.len == 0,
    "no destroys issued -- removed must be empty (got " & $qcr.removed.len & ")"
  doAssert qcr.added.len == 2, "two AddedItems expected (got " & $qcr.added.len & ")"
  for item in qcr.added:
    doAssert ($item.id).len > 0, "added.id must be non-empty"
