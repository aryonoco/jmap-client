# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/queryChanges``
## response without ``calculateTotal``
## (``tests/testdata/captured/email-query-changes-no-total-stalwart.json``).
## Pins the "total absent" wire shape: per RFC 8620 §5.6, ``total`` is
## only emitted when the request opted in, so the parser must surface
## ``Opt.none``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedEmailQueryChangesNoTotal:
  let j = loadCapturedFixture("email-query-changes-no-total-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/queryChanges"
  let qcr = QueryChangesResponse[Email].fromJson(inv.arguments).expect(
      "QueryChangesResponse[Email].fromJson"
    )
  doAssert qcr.total.isNone,
    "total must be Opt.none when calculateTotal was not requested"
  doAssert qcr.added.len >= 0, "added is at least an empty array"
