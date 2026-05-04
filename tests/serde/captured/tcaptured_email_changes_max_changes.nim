# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/changes`` first
## page response under a ``maxChanges`` cap that forces
## ``hasMoreChanges == true``
## (``tests/testdata/captured/email-changes-max-changes-stalwart.json``).
## Verifies that ``ChangesResponse[Email]`` parses the standard
## RFC 8620 §5.2 fields when the response carries the
## "intermediate state" rather than a fully drained delta.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedEmailChangesMaxChanges:
  forEachCapturedServer("email-changes-max-changes", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/changes"

    let cr = ChangesResponse[Email].fromJson(inv.arguments).expect(
        "ChangesResponse[Email].fromJson"
      )
    doAssert ($cr.oldState).len > 0, "oldState must be non-empty"
    doAssert ($cr.newState).len > 0, "newState must be non-empty"
    doAssert string(cr.oldState) != string(cr.newState),
      "first paginated page must advance newState past oldState"
    doAssert cr.hasMoreChanges,
      "the captured page is the first of multiple — hasMoreChanges must be true"
    for id in cr.created:
      doAssert string(id).len > 0, "every created.id must be non-empty"
