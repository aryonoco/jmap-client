# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured compound
## ``EmailSubmission/set`` + implicit ``Email/set`` response with
## ``onSuccessDestroyEmail`` (RFC 8621 §7.5 ¶3 / RFC 8620 §5.4,
## ``tests/testdata/captured/email-submission-on-success-destroy-stalwart.json``).
## Mirrors the Step 34 replay but the implicit Email/set rail
## destroys the referenced Email rather than patching it -- the
## structural difference is ``destroyResults`` (one Ok per
## destroyed id) vs ``updateResults``.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailSubmissionOnSuccessDestroyStalwart:
  forEachCapturedServer("email-submission-on-success-destroy", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 2,
      "compound response must carry both invocations (got " & $resp.methodResponses.len &
        ")"

    var primaryFound = false
    var implicitFound = false
    for inv in resp.methodResponses:
      if inv.rawName == "EmailSubmission/set":
        let setResp = EmailSubmissionSetResponse.fromJson(inv.arguments).expect(
            "EmailSubmissionSetResponse.fromJson"
          )
        doAssert setResp.createResults.len == 1,
          "primary rail must carry exactly one create outcome"
        for cid, outcome in setResp.createResults.pairs:
          doAssert outcome.isOk,
            "primary create must be Ok (got rawType=" & outcome.error.rawType & ")"
          doAssert string(outcome.unsafeValue.id).len > 0,
            "primary create must carry a non-empty id"
          doAssert string(cid).len > 0, "primary creationId must be non-empty"
        primaryFound = true
      elif inv.rawName == "Email/set":
        let setResp = SetResponse[EmailCreatedItem].fromJson(inv.arguments).expect(
            "SetResponse[EmailCreatedItem].fromJson"
          )
        doAssert setResp.destroyResults.len == 1,
          "implicit Email/set rail must carry exactly one destroy outcome"
        for id, outcome in setResp.destroyResults.pairs:
          doAssert outcome.isOk,
            "implicit destroy must be Ok (got rawType=" & outcome.error.rawType & ")"
          doAssert string(id).len > 0, "destroyed draft id must be non-empty"
        implicitFound = true
    doAssert primaryFound, "captured response must contain EmailSubmission/set"
    doAssert implicitFound, "captured response must contain implicit Email/set"
