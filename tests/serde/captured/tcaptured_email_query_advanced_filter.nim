# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/query`` response
## under an advanced filter (``hasAttachment: true`` AND ``before:
## <future date>``)
## (``tests/testdata/captured/email-query-advanced-filter-stalwart.json``).
## Verifies ``QueryResponse[Email]`` parses the standard RFC 8620
## §5.5 frame when an advanced filter is present in the request.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailQueryAdvancedFilter:
  let j = loadCapturedFixture("email-query-advanced-filter-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/query"

  let qr =
    QueryResponse[Email].fromJson(inv.arguments).expect("QueryResponse[Email].fromJson")
  doAssert ($qr.queryState).len > 0, "queryState must be non-empty"
  for id in qr.ids:
    doAssert string(id).len > 0, "every returned id must be non-empty"
