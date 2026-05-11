# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Mailbox/queryChanges``
## response with ``calculateTotal: true``
## (``tests/testdata/captured/mailbox-query-changes-with-total-stalwart.json``).
## Verifies the ``QueryChangesResponse[Mailbox]`` parser handles the
## RFC 8620 §5.6 fields — ``oldQueryState`` / ``newQueryState`` /
## ``total`` / ``removed`` / ``added`` (each ``AddedItem`` carries
## ``id`` and ``index``).

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMailboxQueryChangesWithTotal:
  let j = loadCapturedFixture("mailbox-query-changes-with-total-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Mailbox/queryChanges"

  let qcr = QueryChangesResponse[Mailbox].fromJson(inv.arguments).expect(
      "QueryChangesResponse[Mailbox].fromJson"
    )
  doAssert ($qcr.oldQueryState).len > 0, "oldQueryState must be non-empty"
  doAssert ($qcr.newQueryState).len > 0, "newQueryState must be non-empty"
  doAssert qcr.total.isSome,
    "total must be present when calculateTotal=true was requested"
  for item in qcr.added:
    doAssert string(item.id).len > 0, "added.id must be non-empty"
