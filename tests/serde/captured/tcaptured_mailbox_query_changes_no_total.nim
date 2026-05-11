# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Mailbox/queryChanges``
## response without ``calculateTotal``
## (``tests/testdata/captured/mailbox-query-changes-no-total-stalwart.json``).
## Verifies the ``QueryChangesResponse[Mailbox]`` parser correctly
## projects the absent ``total`` field as ``Opt.none`` per RFC 8620
## §5.6 — ``total`` is only present when the request opted in via
## ``calculateTotal: true``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMailboxQueryChangesNoTotal:
  let j = loadCapturedFixture("mailbox-query-changes-no-total-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Mailbox/queryChanges"

  let qcr = QueryChangesResponse[Mailbox].fromJson(inv.arguments).expect(
      "QueryChangesResponse[Mailbox].fromJson"
    )
  doAssert ($qcr.oldQueryState).len > 0, "oldQueryState must be non-empty"
  doAssert ($qcr.newQueryState).len > 0, "newQueryState must be non-empty"
  doAssert qcr.total.isNone,
    "total must be absent when calculateTotal was not requested"
