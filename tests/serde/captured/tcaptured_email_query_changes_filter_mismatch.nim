# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/queryChanges``
## response under a filter mismatch
## (``tests/testdata/captured/email-query-changes-filter-mismatch-stalwart.json``).
## Empirical pin: Stalwart 0.15.5 chooses the RFC 8620 §5.6 "Ok with
## fresh delta" branch rather than the ``cannotCalculateChanges``
## branch — silently recomputing against the new filter.  The
## response carries the standard ``oldQueryState`` / ``newQueryState``
## / ``removed`` / ``added`` fields with no ``total`` (calculateTotal
## was not requested in the original /queryChanges call).

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailQueryChangesFilterMismatch:
  let j = loadCapturedFixture("email-query-changes-filter-mismatch-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/queryChanges"

  let qcr = QueryChangesResponse[Email].fromJson(inv.arguments).expect(
      "QueryChangesResponse[Email].fromJson"
    )
  doAssert ($qcr.oldQueryState).len > 0, "oldQueryState must be non-empty"
  doAssert ($qcr.newQueryState).len > 0, "newQueryState must be non-empty"
  doAssert qcr.total.isNone, "calculateTotal was not requested — total must be absent"
  for item in qcr.added:
    doAssert string(item.id).len > 0, "every added.id must be non-empty"
