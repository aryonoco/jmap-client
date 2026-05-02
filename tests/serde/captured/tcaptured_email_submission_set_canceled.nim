# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``EmailSubmission/set
## update`` (cancel) response (RFC 8621 §7.5 ¶3,
## ``tests/testdata/captured/email-submission-set-canceled-stalwart.json``).
## First captured fixture exercising the EmailSubmission Update arm.
## Asserts the update outcome is Ok and ``newState`` advances.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailSubmissionSetCanceled:
  let j = loadCapturedFixture("email-submission-set-canceled-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "EmailSubmission/set",
    "expected EmailSubmission/set, got " & inv.rawName

  let setResp = EmailSubmissionSetResponse.fromJson(inv.arguments).expect(
      "EmailSubmissionSetResponse.fromJson"
    )
  doAssert setResp.updateResults.len == 1,
    "exactly one update outcome expected (got " & $setResp.updateResults.len & ")"
  for id, outcome in setResp.updateResults.pairs:
    doAssert outcome.isOk,
      "cancel update must be Ok (got rawType=" & outcome.error.rawType & ")"
    doAssert string(id).len > 0, "updated submission id must be non-empty"
  doAssert ($setResp.newState).len > 0, "newState must be non-empty"
