# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``EmailSubmission/changes``
## happy + sad pair (RFC 8621 §7.2 / RFC 8620 §5.5,
## ``tests/testdata/captured/email-submission-changes-stalwart.json``).
## Two invocations on distinct call ids: the first carries the typed
## ``ChangesResponse[AnyEmailSubmission]`` for the well-formed
## ``sinceState`` request; the second carries an ``error`` invocation
## (``rawName == "error"``) projecting Stalwart 0.15.5's bogus-state
## response. RFC 8620 §5.5 permits either ``cannotCalculateChanges`` or
## ``invalidArguments`` -- the assertion uses set membership so both
## RFC-compliant projections continue to pass.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailSubmissionChangesStalwart:
  let j = loadCapturedFixture("email-submission-changes-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 2,
    "captured response must carry both invocations (got " & $resp.methodResponses.len &
      ")"

  var happyFound = false
  var sadFound = false
  for inv in resp.methodResponses:
    if inv.rawName == "EmailSubmission/changes":
      let cr = ChangesResponse[AnyEmailSubmission].fromJson(inv.arguments).expect(
          "ChangesResponse[AnyEmailSubmission].fromJson"
        )
      doAssert ($cr.oldState).len > 0, "oldState must be non-empty"
      doAssert ($cr.newState).len > 0, "newState must be non-empty"
      doAssert cr.created.len == 2,
        "two created entries expected (got " & $cr.created.len & ")"
      doAssert cr.updated.len == 0,
        "no updated entries expected (got " & $cr.updated.len & ")"
      doAssert cr.destroyed.len == 0,
        "no destroyed entries expected (got " & $cr.destroyed.len & ")"
      happyFound = true
    elif inv.rawName == "error":
      let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
      doAssert me.errorType in {metCannotCalculateChanges, metInvalidArguments},
        "method error must project as cannotCalculateChanges or invalidArguments " &
          "(got " & $me.errorType & ", rawType=" & me.rawType & ")"
      sadFound = true
  doAssert happyFound,
    "captured response must contain the EmailSubmission/changes happy invocation"
  doAssert sadFound, "captured response must contain the bogus-state error invocation"
