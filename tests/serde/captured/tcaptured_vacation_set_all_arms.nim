# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``VacationResponse/set``
## response covering all three new update arms (``setHtmlBody``,
## ``setFromDate``, ``setToDate``) plus the three from Phase B9
## (``tests/testdata/captured/vacation-set-all-arms-stalwart.json``).
## Verifies that ``SetResponse[VacationResponse]`` parses the
## ``updated`` table where the singleton key maps to ``null``
## (RFC 8620 §5.3 — server-defined fields unchanged from the
## client's submission).

{.push raises: [], hint[XCannotRaiseY]: off.}

import std/json
import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedVacationSetAllArms:
  forEachCapturedServer("vacation-set-all-arms", j):
    # Two server-specific shapes are RFC-conformant here:
    #   * Stalwart and James implement VacationResponse/set and emit
    #     an envelope.Response carrying the singleton ``updateResults``
    #     entry.
    #   * Cyrus 3.12.2 ships VacationResponse but the test image
    #     disables it via ``imapd.conf: jmap_vacation: no``; the
    #     request-level problem-details rejects with
    #     ``unknownCapability``. The wire shape is RFC 7807, not an
    #     envelope.Response. The universal client-library contract
    #     here is the typed-error projection.
    if j.hasKey("methodResponses"):
      let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
      doAssert resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      doAssert inv.rawName == "VacationResponse/set"

      let setResp = SetResponse[VacationResponse].fromJson(inv.arguments).expect(
          "SetResponse[VacationResponse].fromJson"
        )
      doAssert setResp.newState.isSome, "newState must be present in this fixture"
      let singletonId =
        parseIdFromServer("singleton").expect("parseIdFromServer singleton")
      doAssert singletonId in setResp.updateResults,
        "VacationResponse/set must report a singleton update outcome"
      let outcome = setResp.updateResults[singletonId]
      doAssert outcome.isOk,
        "VacationResponse/set update with all six arms must succeed for the singleton"
    else:
      let re = RequestError.fromJson(j).expect("RequestError.fromJson")
      doAssert re.errorType == retUnknownCapability,
        "Cyrus rejection must project as retUnknownCapability; got " & $re.errorType
