# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``VacationResponse/get``
## singleton response (RFC 8621 §7,
## ``tests/testdata/captured/vacation-get-singleton-stalwart.json``).
## After the live test enables vacation auto-reply, the singleton
## carries ``isEnabled = true`` plus the configured ``subject`` /
## ``textBody``; the parser must round-trip through
## ``VacationResponse.fromJson`` / ``toJson``.

{.push raises: [].}

import jmap_client
import ./mloader

block tcapturedVacationGet:
  let j = loadCapturedFixture("vacation-get-singleton-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "VacationResponse/get"
  let getResp = GetResponse[VacationResponse].fromJson(inv.arguments).expect(
      "GetResponse[VacationResponse].fromJson"
    )
  doAssert getResp.list.len == 1,
    "VacationResponse is a singleton — exactly one entry expected"
  let vr =
    VacationResponse.fromJson(getResp.list[0]).expect("VacationResponse.fromJson")
  doAssert vr.isEnabled, "captured fixture corresponds to enabled state"
  doAssert vr.subject.isSome, "captured fixture sets a subject"
  doAssert vr.textBody.isSome, "captured fixture sets a textBody"
  let rt = VacationResponse.fromJson(vr.toJson()).expect("VacationResponse round-trip")
  doAssert rt.isEnabled == vr.isEnabled, "isEnabled must round-trip"
  doAssert rt.subject == vr.subject, "subject must round-trip"
  doAssert rt.textBody == vr.textBody, "textBody must round-trip"
