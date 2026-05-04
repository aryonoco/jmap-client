# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured
## ``EmailSubmission/query`` response carrying the result of a
## ``threadId``-sorted comparator (``tests/testdata/captured/
## email-submission-filter-completeness-stalwart.json``).
##
## This fixture is the last leg of Phase J Step 71's six-leg
## envelope chain — earlier legs exercised the four
## ``EmailSubmissionFilterCondition`` variants (``threadIds``,
## ``emailIds``, ``undoStatus``, ``before``/``after``) and the
## ``emailId`` comparator; the captured ``threadId`` comparator
## response confirms the typed surface parses cleanly.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailSubmissionFilterCompleteness:
  let j = loadCapturedFixture("email-submission-filter-completeness-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/query",
    "fixture is the last leg — sort by threadId asc; got " & inv.rawName
  let qResp = QueryResponse[AnyEmailSubmission].fromJson(inv.arguments).expect(
      "QueryResponse[AnyEmailSubmission].fromJson"
    )
  doAssert qResp.ids.len >= 2,
    "Phase J corpus seeds two submissions; got " & $qResp.ids.len
  doAssert ($qResp.queryState).len > 0, "queryState must be populated"
