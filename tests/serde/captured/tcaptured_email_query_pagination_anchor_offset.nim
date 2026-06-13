# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` anchor +
## anchorOffset response (RFC 8620 §5.5,
## ``tests/testdata/captured/email-query-pagination-anchor-offset-stalwart.json``).
## Verifies the response parses cleanly. Anchor+offset window-sizing
## is server-implementation-defined in practice; the structural
## parser-level assertion is that the response contains at least one
## id and has a non-empty queryState.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailQueryPaginationAnchorOffset:
  let j = loadCapturedFixture("email-query-pagination-anchor-offset-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/query", "expected Email/query, got " & inv.rawName
  let qr =
    QueryResponse[Email].fromJson(inv.arguments).expect("QueryResponse[Email].fromJson")
  doAssert qr.ids.len >= 1,
    "anchor+offset response must contain at least one id (got " & $qr.ids.len & ")"
  doAssert ($qr.queryState).len > 0, "queryState must be non-empty"
