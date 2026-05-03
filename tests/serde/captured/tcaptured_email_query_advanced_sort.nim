# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` response
## under a ``hasKeyword`` keyword sort
## (``tests/testdata/captured/email-query-advanced-sort-stalwart.json``).
## Verifies ``QueryResponse[Email].fromJson`` parses the standard
## RFC 8620 §5.5 frame when the original request used the
## eckKeyword EmailComparator arm.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailQueryAdvancedSort:
  let j = loadCapturedFixture("email-query-advanced-sort-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/query"

  let qr =
    QueryResponse[Email].fromJson(inv.arguments).expect("QueryResponse[Email].fromJson")
  doAssert ($qr.queryState).len > 0, "queryState must be non-empty"
  doAssert qr.ids.len >= 3,
    "phase-i 56 keyword-sort capture must surface at least three seeded emails (got " &
      $qr.ids.len & ")"
  for id in qr.ids:
    doAssert string(id).len > 0, "every returned id must be non-empty"
