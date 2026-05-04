# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``EmailSubmission/set
## destroy`` response on a freshly-canceled submission (RFC 8621 §7.5,
## ``tests/testdata/captured/email-submission-destroy-canceled-stalwart.json``).
## First captured fixture exercising the EmailSubmission Destroy arm —
## Phase F's six EmailSubmission fixtures all exercised the Create
## arm; Phase G Step 41 added Update; this fixture closes the third
## arm. Asserts the destroy outcome is Ok and ``newState`` advances.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailSubmissionDestroyCanceled:
  let j = loadCapturedFixture("email-submission-destroy-canceled-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/set",
    "expected EmailSubmission/set, got " & inv.rawName

  let setResp = EmailSubmissionSetResponse.fromJson(inv.arguments).expect(
      "EmailSubmissionSetResponse.fromJson"
    )
  doAssert setResp.destroyResults.len == 1,
    "exactly one destroy outcome expected (got " & $setResp.destroyResults.len & ")"
  for id, outcome in setResp.destroyResults.pairs:
    doAssert outcome.isOk,
      "destroy of canceled submission must be Ok (got rawType=" & outcome.error.rawType &
        ")"
    doAssert string(id).len > 0, "destroyed submission id must be non-empty"
  doAssert setResp.newState.isSome, "newState must be present in this fixture"
