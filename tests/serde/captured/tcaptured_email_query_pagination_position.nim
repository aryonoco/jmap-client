# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` response
## with ``position=2, limit=2, calculateTotal=true`` (RFC 8620 §5.5,
## ``tests/testdata/captured/email-query-pagination-position-stalwart.json``).
## Verifies the position window and total surface correctly.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailQueryPaginationPosition:
  let j = loadCapturedFixture("email-query-pagination-position-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/query", "expected Email/query, got " & inv.rawName
  let qr =
    QueryResponse[Email].fromJson(inv.arguments).expect("QueryResponse[Email].fromJson")
  doAssert qr.position == UnsignedInt(2),
    "position must echo requested 2 (got " & $qr.position & ")"
  doAssert qr.ids.len == 2,
    "limit=2 must yield exactly two ids (got " & $qr.ids.len & ")"
  doAssert qr.total.isSome, "calculateTotal=true must surface total"
  doAssert qr.total.unsafeGet >= UnsignedInt(5),
    "total must be at least the seeded 5 (got " & $qr.total.unsafeGet & ")"
