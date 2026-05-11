# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``EmailSubmission/query``
## response under a ``sentAt`` ascending sort
## (``tests/testdata/captured/email-submission-query-filter-sort-stalwart.json``).
## Verifies that ``QueryResponse[AnyEmailSubmission].fromJson``
## parses the standard RFC 8620 §5.5 frame for the EmailSubmission
## entity (RFC 8621 §7.3).

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailSubmissionQueryFilterSort:
  let j = loadCapturedFixture("email-submission-query-filter-sort-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/query"

  let qr = QueryResponse[AnyEmailSubmission].fromJson(inv.arguments).expect(
      "QueryResponse[AnyEmailSubmission].fromJson"
    )
  doAssert ($qr.queryState).len > 0, "queryState must be non-empty"
  doAssert qr.ids.len >= 2,
    "phase-i 60 capstone seeded at least two submissions (got " & $qr.ids.len & ")"
  for id in qr.ids:
    doAssert string(id).len > 0, "every returned submission id must be non-empty"
