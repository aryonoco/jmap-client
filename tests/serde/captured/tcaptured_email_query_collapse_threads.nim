# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` response
## under ``collapseThreads = true``
## (``tests/testdata/captured/email-query-collapse-threads-stalwart.json``).
## Verifies that ``QueryResponse[Email].fromJson`` parses the
## standard RFC 8620 §5.5 frame when the request set
## ``collapseThreads: true`` per RFC 8621 §4.4.3.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailQueryCollapseThreads:
  forEachCapturedServer("email-query-collapse-threads", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/query"

    let qr = QueryResponse[Email].fromJson(inv.arguments).expect(
        "QueryResponse[Email].fromJson"
      )
    doAssert ($qr.queryState).len > 0, "queryState must be non-empty"
    doAssert qr.ids.len >= 2,
      "collapseThreads=true must surface at least one entry per thread (got " &
        $qr.ids.len & ")"
    for id in qr.ids:
      doAssert string(id).len > 0, "every returned id must be non-empty"
