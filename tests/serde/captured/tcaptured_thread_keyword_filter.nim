# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` response
## carrying a ``noneInThreadHaveKeyword`` filter result
## (``tests/testdata/captured/thread-keyword-filter-stalwart.json``).
##
## Verifies the ``QueryResponse[Email]`` parser handles the wire
## shape produced by a thread-keyword-filtered query.  The Phase J
## Step 72 live test already exercised the wire-emission for all
## three ``allInThread`` / ``someInThread`` / ``noneInThread``
## variants; this replay pins Stalwart's response shape on the
## ``noneInThreadHaveKeyword`` leg.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedThreadKeywordFilter:
  let j = loadCapturedFixture("thread-keyword-filter-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/query",
    "fixture is the noneInThreadHaveKeyword Email/query leg; got " & inv.rawName
  let qResp =
    QueryResponse[Email].fromJson(inv.arguments).expect("QueryResponse[Email].fromJson")
  doAssert ($qResp.queryState).len > 0, "queryState must be populated"
  doAssert qResp.canCalculateChanges, "Stalwart advertises canCalculateChanges=true"
