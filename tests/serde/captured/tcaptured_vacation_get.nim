# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``VacationResponse/get``
## singleton response (RFC 8621 §7,
## ``tests/testdata/captured/vacation-get-singleton-stalwart.json``).
## After the live test enables vacation auto-reply, the singleton
## carries ``isEnabled = true`` plus the configured ``subject`` /
## ``textBody``; the parser must round-trip through
## ``VacationResponse.fromJson`` / ``toJson``.

{.push raises: [], hint[XCannotRaiseY]: off.}

import std/json

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedVacationGet:
  forEachCapturedServer("vacation-get-singleton", j):
    # Two server-specific shapes are RFC-conformant here:
    #   * Stalwart and James implement VacationResponse and emit an
    #     envelope.Response carrying the singleton ``VacationResponse/
    #     get`` invocation with the configured fields.
    #   * Cyrus 3.12.2 ships VacationResponse but the test image
    #     disables it via ``imapd.conf: jmap_vacation: no``; the
    #     request-level problem-details rejects with
    #     ``unknownCapability``. The wire shape is RFC 7807, not an
    #     envelope.Response. The universal client-library contract
    #     here is the typed-error projection — exercised by the live
    #     test in ``tvacation_get_set_live.nim`` and the integrity
    #     test in ``tcaptured_round_trip_integrity.nim``.
    if j.hasKey("methodResponses"):
      let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
      doAssert resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      doAssert inv.rawName == "VacationResponse/get"
      let getResp = GetResponse[VacationResponse].fromJson(inv.arguments).expect(
          "GetResponse[VacationResponse].fromJson"
        )
      doAssert getResp.list.len == 1,
        "VacationResponse is a singleton — exactly one entry expected"
      let vr = getResp.list[0]
      doAssert vr.isEnabled, "captured fixture corresponds to enabled state"
      doAssert vr.subject.isSome, "captured fixture sets a subject"
      doAssert vr.textBody.isSome, "captured fixture sets a textBody"
      let rt =
        VacationResponse.fromJson(vr.toJson()).expect("VacationResponse round-trip")
      doAssert rt.isEnabled == vr.isEnabled, "isEnabled must round-trip"
      doAssert rt.subject == vr.subject, "subject must round-trip"
      doAssert rt.textBody == vr.textBody, "textBody must round-trip"
    else:
      let re = RequestError.fromJson(j).expect("RequestError.fromJson")
      doAssert re.errorType == retUnknownCapability,
        "Cyrus rejection must project as retUnknownCapability; got " & $re.errorType
