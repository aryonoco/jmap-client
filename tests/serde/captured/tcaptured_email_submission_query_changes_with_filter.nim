# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured
## ``EmailSubmission/queryChanges`` response with
## ``calculateTotal: true``
## (``tests/testdata/captured/email-submission-query-changes-with-filter-stalwart.json``).
## Verifies that ``QueryChangesResponse[AnyEmailSubmission].fromJson``
## parses the RFC 8620 §5.6 fields for the EmailSubmission entity.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailSubmissionQueryChangesWithFilter:
  let j = loadCapturedFixture("email-submission-query-changes-with-filter-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/queryChanges"

  let qcr = QueryChangesResponse[AnyEmailSubmission].fromJson(inv.arguments).expect(
      "QueryChangesResponse[AnyEmailSubmission].fromJson"
    )
  doAssert ($qcr.oldQueryState).len > 0, "oldQueryState must be non-empty"
  doAssert ($qcr.newQueryState).len > 0, "newQueryState must be non-empty"
  doAssert qcr.total.isSome,
    "calculateTotal=true must surface a total in queryChanges response"
  doAssert qcr.added.len >= 4,
    "phase-i 60 capstone added at least four submissions (got " & $qcr.added.len & ")"
  for item in qcr.added:
    doAssert string(item.id).len > 0, "added.id must be non-empty"
