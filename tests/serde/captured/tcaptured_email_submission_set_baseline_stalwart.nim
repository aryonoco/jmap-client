# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``EmailSubmission/set``
## baseline create response (RFC 8621 §7.5,
## ``tests/testdata/captured/email-submission-set-baseline-stalwart.json``).
## Asserts that ``EmailSubmissionSetResponse.fromJson`` lifts the
## minimal Stalwart payload ``{"id": "<id>"}`` into an Ok-rail
## ``EmailSubmissionCreatedItem`` with ``threadId`` and ``sendAt``
## absent (the Postel's-law accommodation documented at the
## ``serde_email_submission`` parser).

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailSubmissionSetBaselineStalwart:
  forEachCapturedServer("email-submission-set-baseline", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "EmailSubmission/set",
      "expected EmailSubmission/set, got " & inv.rawName
    let setResp = EmailSubmissionSetResponse.fromJson(inv.arguments).expect(
        "EmailSubmissionSetResponse.fromJson"
      )
    doAssert setResp.createResults.len == 1,
      "exactly one create outcome expected (got " & $setResp.createResults.len & ")"
    for cid, outcome in setResp.createResults.pairs:
      doAssert outcome.isOk,
        "create outcome must be Ok (got rawType=" & outcome.error.rawType & ")"
      let item = outcome.unsafeValue
      doAssert string(item.id).len > 0, "created id must be non-empty"
      doAssert string(cid).len > 0, "creationId must be non-empty"
    doAssert setResp.newState.isSome, "newState must be present in this fixture"
