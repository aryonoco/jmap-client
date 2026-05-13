# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Mailbox/query`` response
## with name filter + sortOrder ascending sort
## (``tests/testdata/captured/mailbox-query-filter-sort-stalwart.json``).
## Verifies that ``QueryResponse[Mailbox]`` parses the standard RFC 8620
## §5.5 fields — ``queryState``, ``canCalculateChanges``, ``position``,
## ``ids`` — when filter and sort are present in the original request.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedMailboxQueryFilterSort:
  let j = loadCapturedFixture("mailbox-query-filter-sort-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Mailbox/query"

  let qr = QueryResponse[Mailbox].fromJson(inv.arguments).expect(
      "QueryResponse[Mailbox].fromJson"
    )
  doAssert ($qr.queryState).len > 0, "queryState must be non-empty"
  doAssert qr.ids.len >= 3,
    "filter name=phase-i 49 must surface at least three mailboxes (got " & $qr.ids.len &
      ")"
  for id in qr.ids:
    doAssert ($id).len > 0, "every returned id must be non-empty"
